export const DEFAULT_DATE_FORMATS = ["yyyyMMdd", "yyyy/MM/dd", "yyyy年MM月dd日"];
export const MAX_DATE_FORMATS = 10;
export const MAX_DATE_FORMAT_CHARS = 64;
const TOKENS = ["yyyy", "yy", "MM", "M", "dd", "d"];

export const normalizeDateFormats = (value) => {
    if (value === undefined) return [...DEFAULT_DATE_FORMATS];
    if (!Array.isArray(value) || value.some((format) => typeof format !== "string")) {
        throw new Error("日付形式の設定が不正です");
    }
    return [...value];
};

export const validateDateFormats = (formats) => {
    if (formats.length < 1 || formats.length > MAX_DATE_FORMATS) {
        return `日付形式は1〜${MAX_DATE_FORMATS}件で指定してください`;
    }
    for (const [index, format] of formats.entries()) {
        let error = "";
        if (!format.trim()) error = "空の形式は使えません";
        else if (Array.from(format).length > MAX_DATE_FORMAT_CHARS) error = `${MAX_DATE_FORMAT_CHARS}文字以内で指定してください`;
        else {
            let remaining = format;
            let hasToken = false;
            while (remaining) {
                const token = TOKENS.find((candidate) => remaining.startsWith(candidate));
                if (token) {
                    hasToken = true;
                    remaining = remaining.slice(token.length);
                    continue;
                }
                const character = String.fromCodePoint(remaining.codePointAt(0));
                if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/u.test(character)) {
                    error = "改行や制御文字は使えません";
                    break;
                }
                if (/[a-z]/i.test(character)) {
                    error = "使えるトークンは yyyy・yy・MM・M・dd・d です";
                    break;
                }
                remaining = remaining.slice(character.length);
            }
            if (!error && !hasToken) error = "日付のトークンを1つ以上含めてください";
        }
        if (error) return `${index + 1}行目: ${error}`;
    }
    return "";
};

export const previewDateFormat = (format, date) => {
    if (validateDateFormats([format])) return "";
    const year = String(date.getFullYear()).padStart(4, "0");
    const month = String(date.getMonth() + 1);
    const day = String(date.getDate());
    const values = { yyyy: year, yy: year.slice(-2), MM: month.padStart(2, "0"), M: month, dd: day.padStart(2, "0"), d: day };
    return format.replace(/yyyy|yy|MM|M|dd|d/g, (token) => values[token]);
};
