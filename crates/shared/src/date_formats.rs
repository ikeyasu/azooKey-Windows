pub const MAX_DATE_FORMATS: usize = 10;
pub const MAX_DATE_FORMAT_CHARS: usize = 64;

pub fn default_date_formats() -> Vec<String> {
    ["yyyyMMdd", "yyyy/MM/dd", "yyyy年MM月dd日"]
        .map(str::to_owned)
        .to_vec()
}

/// Validates the small, locale-independent format language used for date candidates.
/// Unicode literals are preserved; ASCII letters must form a supported date token.
pub fn validate_date_formats(formats: &[String]) -> Result<(), String> {
    if formats.is_empty() || formats.len() > MAX_DATE_FORMATS {
        return Err(format!(
            "日付形式は1〜{MAX_DATE_FORMATS}件で指定してください"
        ));
    }
    for (index, format) in formats.iter().enumerate() {
        let invalid = if format.trim().is_empty() {
            Some("空の形式は使えません".to_owned())
        } else if format.chars().count() > MAX_DATE_FORMAT_CHARS {
            Some(format!("{MAX_DATE_FORMAT_CHARS}文字以内で指定してください"))
        } else {
            validate_date_format(format).err()
        };
        if let Some(message) = invalid {
            return Err(format!("{}行目: {message}", index + 1));
        }
    }
    Ok(())
}

fn validate_date_format(mut remaining: &str) -> Result<(), String> {
    let mut has_token = false;
    while !remaining.is_empty() {
        if let Some(token) = ["yyyy", "yy", "MM", "M", "dd", "d"]
            .into_iter()
            .find(|token| remaining.starts_with(token))
        {
            has_token = true;
            remaining = &remaining[token.len()..];
            continue;
        }
        let character = remaining.chars().next().unwrap();
        if character.is_control() || matches!(character, '\u{2028}' | '\u{2029}') {
            return Err("改行や制御文字は使えません".to_owned());
        }
        if character.is_ascii_alphabetic() {
            return Err("使えるトークンは yyyy・yy・MM・M・dd・d です".to_owned());
        }
        remaining = &remaining[character.len_utf8()..];
    }
    if !has_token {
        return Err("日付のトークンを1つ以上含めてください".to_owned());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_supported_tokens_and_unicode_literals_without_changing_order() {
        let formats = vec![
            "yy年M月d日".to_owned(),
            " yyyy-MM-dd（今日）🗓 ".to_owned(),
            "yyyyMMdd".to_owned(),
        ];
        assert_eq!(validate_date_formats(&formats), Ok(()));
        assert_eq!(formats[0], "yy年M月d日");
        assert!(validate_date_formats(&default_date_formats()).is_ok());
    }

    #[test]
    fn rejects_empty_missing_tokens_unsupported_tokens_and_controls() {
        assert!(validate_date_formats(&[]).is_err());
        for format in [
            "",
            "　 ",
            "今日の日付",
            "2026/11/13",
            "yyyy/MM/dd HH:mm",
            "YYYY/MM/dd",
            "yyy/M/d",
            "yyyy\nd",
            "yyyy\td",
            "yyyy\rd",
            "yyyy\0d",
            "yyyy\u{85}d",
            "yyyy\u{2028}d",
            "yyyy\u{2029}d",
        ] {
            let formats = vec!["yyyyMMdd".to_owned(), format.to_owned()];
            let error = validate_date_formats(&formats).unwrap_err();
            assert!(error.starts_with("2行目:"), "{format:?}: {error}");
        }
    }

    #[test]
    fn bounds_format_count_and_unicode_scalar_length() {
        assert!(validate_date_formats(&vec!["d".to_owned(); MAX_DATE_FORMATS]).is_ok());
        assert!(validate_date_formats(&vec!["d".to_owned(); MAX_DATE_FORMATS + 1]).is_err());
        let exact = format!("d{}", "🗓".repeat(MAX_DATE_FORMAT_CHARS - 1));
        assert!(validate_date_formats(&[exact.clone()]).is_ok());
        assert!(validate_date_formats(&[format!("{exact}日")]).is_err());
    }
}
