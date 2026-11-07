//! iOS media preparation: download a CENC episode/chapter and strip the
//! encryption into the app cache before handing it to AVPlayer.
//!
//! The Android host streams decrypted bytes into ExoPlayer through the C
//! `sp_stream` adapter. AVPlayer on iOS cannot decrypt CENC MP4 itself, so the
//! iOS host asks the core for a plaintext local file first and plays that. The
//! trade-off is a wait for the first frame instead of a custom AVAsset loader;
//! it keeps the decryption in one audited implementation and avoids a second
//! CENC parser in Swift.

use std::path::{Path, PathBuf};

use futures::StreamExt;
use sha2::{Digest, Sha256};

use crate::endpoints::video::decrypt_media_bytes;

/// Refuse absurd payloads instead of exhausting the phone's memory/disk.
const MAX_MEDIA_BYTES: u64 = 512 * 1024 * 1024;

/// The player download UA mirrors the short-drama downloader: CDNs sometimes
/// answer differently to OkHttp/reqwest defaults.
const MEDIA_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

/// Downloads `url` (http/https or file://) and, when `key_hex` is non-empty,
/// writes a decrypted copy under `cache_dir`. Returns the absolute path.
///
/// The cache name is a hash of the source URL and key, so reopening the same
/// episode reuses the plaintext file while a rotated key produces a new entry.
/// A failed download or decrypt leaves no partial file behind.
pub async fn prepare_media(
    url: String,
    key_hex: String,
    cache_dir: String,
) -> Result<String, String> {
    let trimmed_url = url.trim();
    if trimmed_url.is_empty() {
        return Err("媒体地址为空".to_string());
    }
    let key = decode_key(&key_hex)?;
    let directory = PathBuf::from(cache_dir);
    tokio::fs::create_dir_all(&directory)
        .await
        .map_err(|e| format!("创建媒体缓存目录失败: {e}"))?;

    let mut hasher = Sha256::new();
    hasher.update(trimmed_url.as_bytes());
    hasher.update(b"|");
    hasher.update(key_hex.trim().as_bytes());
    let digest = hasher.finalize();
    let target = directory.join(format!("{}.mp4", hex::encode(digest)));
    if let Ok(meta) = tokio::fs::metadata(&target).await {
        if meta.is_file() && meta.len() > 0 {
            return Ok(target.to_string_lossy().into_owned());
        }
    }

    let mut bytes = if trimmed_url.starts_with("file://") {
        read_local_media(trimmed_url).await?
    } else {
        download_media(trimmed_url).await?
    };

    if !key.is_empty() {
        decrypt_media_bytes(&mut bytes, &key)?;
    }

    let part = target.with_extension(format!("mp4.{}.part", std::process::id()));
    tokio::fs::write(&part, &bytes)
        .await
        .map_err(|e| format!("写入媒体缓存失败: {e}"))?;
    if let Err(error) = tokio::fs::rename(&part, &target).await {
        let _ = tokio::fs::remove_file(&part).await;
        // Another caller may have finished the same entry first; that copy is
        // equivalent, so reuse it instead of failing playback.
        if let Ok(meta) = tokio::fs::metadata(&target).await {
            if meta.is_file() && meta.len() > 0 {
                return Ok(target.to_string_lossy().into_owned());
            }
        }
        return Err(format!("保存媒体缓存失败: {error}"));
    }
    Ok(target.to_string_lossy().into_owned())
}

fn decode_key(key_hex: &str) -> Result<Vec<u8>, String> {
    let trimmed = key_hex.trim();
    if trimmed.is_empty() {
        return Ok(Vec::new());
    }
    let key = hex::decode(trimmed).map_err(|_| "媒体密钥格式无效".to_string())?;
    if !matches!(key.len(), 16 | 24 | 32) {
        return Err("媒体密钥长度无效".to_string());
    }
    Ok(key)
}

async fn read_local_media(url: &str) -> Result<Vec<u8>, String> {
    let path = url::Url::parse(url)
        .ok()
        .and_then(|parsed| parsed.to_file_path().ok())
        .ok_or_else(|| "本地媒体路径无效".to_string())?;
    read_file_limited(&path).await
}

async fn read_file_limited(path: &Path) -> Result<Vec<u8>, String> {
    let meta = tokio::fs::metadata(path)
        .await
        .map_err(|e| format!("读取媒体失败: {e}"))?;
    if meta.len() > MAX_MEDIA_BYTES {
        return Err("媒体文件过大".to_string());
    }
    tokio::fs::read(path)
        .await
        .map_err(|e| format!("读取媒体失败: {e}"))
}

async fn download_media(url: &str) -> Result<Vec<u8>, String> {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(180))
        .build()
        .map_err(|e| format!("初始化下载器失败: {e}"))?;
    let response = client
        .get(url)
        .header(reqwest::header::USER_AGENT, MEDIA_USER_AGENT)
        .header(reqwest::header::ACCEPT_ENCODING, "identity")
        .send()
        .await
        .map_err(|e| format!("下载媒体失败: {e}"))?;
    if !response.status().is_success() {
        return Err(format!("下载媒体失败: HTTP {}", response.status().as_u16()));
    }
    if let Some(length) = response.content_length() {
        if length > MAX_MEDIA_BYTES {
            return Err("媒体文件过大".to_string());
        }
    }
    let mut body = Vec::with_capacity(response.content_length().unwrap_or(0) as usize);
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| format!("下载媒体中断: {e}"))?;
        if body.len() as u64 + chunk.len() as u64 > MAX_MEDIA_BYTES {
            return Err("媒体文件过大".to_string());
        }
        body.extend_from_slice(&chunk);
    }
    if body.is_empty() {
        return Err("下载到的媒体为空".to_string());
    }
    Ok(body)
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;

    const FIXTURE: &str = include_str!("../../testdata/cenc_sample_fixture.json");

    fn fixture() -> serde_json::Value {
        serde_json::from_str(FIXTURE).expect("cenc_sample_fixture.json")
    }

    fn unique_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "fqapp-media-cache-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[tokio::test]
    async fn decrypts_a_local_cenc_file_and_reuses_the_cache() {
        let f = fixture();
        let c = &f["cenc"];
        let encrypted = base64::engine::general_purpose::STANDARD
            .decode(c["full_sample_b64"].as_str().unwrap())
            .unwrap();
        let key_hex = c["key_hex"].as_str().unwrap().to_string();
        let key = hex::decode(&key_hex).unwrap();
        let mut expected = encrypted.clone();
        decrypt_media_bytes(&mut expected, &key).unwrap();
        assert_ne!(expected, encrypted, "fixture must actually be encrypted");

        let dir = unique_dir("local");
        let source = dir.join("episode.mp4");
        std::fs::write(&source, &encrypted).unwrap();
        let cache = dir.join("cache");

        let url = url::Url::from_file_path(&source).unwrap().to_string();
        let first = prepare_media(url.clone(), key_hex.clone(), cache.to_string_lossy().into_owned())
            .await
            .expect("prepare local media");
        let plain = std::fs::read(&first).unwrap();
        assert_eq!(plain, expected, "decrypted cache must match the fixture plaintext");

        let second = prepare_media(url, key_hex, cache.to_string_lossy().into_owned())
            .await
            .expect("second prepare hits the cache");
        assert_eq!(first, second);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn clears_no_key_copy_without_touching_the_bytes() {
        let f = fixture();
        let c = &f["cenc"];
        let encrypted = base64::engine::general_purpose::STANDARD
            .decode(c["full_sample_b64"].as_str().unwrap())
            .unwrap();

        let dir = unique_dir("nokey");
        let source = dir.join("episode.mp4");
        std::fs::write(&source, &encrypted).unwrap();
        let cache = dir.join("cache");
        let url = url::Url::from_file_path(&source).unwrap().to_string();
        let out = prepare_media(url, String::new(), cache.to_string_lossy().into_owned())
            .await
            .expect("prepare without a key");
        assert_eq!(std::fs::read(out).unwrap(), encrypted);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
