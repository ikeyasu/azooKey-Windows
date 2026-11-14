import test from "node:test";
import assert from "node:assert/strict";
import {
    DEFAULT_DATE_FORMATS, MAX_DATE_FORMATS, MAX_DATE_FORMAT_CHARS,
    normalizeDateFormats, previewDateFormat, validateDateFormats,
} from "../src/lib/date-formats.js";

test("default date formats show the requested local date candidates in order", () => {
    const today = new Date(2026, 10, 13, 0, 5);
    assert.deepEqual(DEFAULT_DATE_FORMATS.map((format) => previewDateFormat(format, today)), ["20261113", "2026/11/13", "2026年11月13日"]);
    assert.equal(previewDateFormat("yy年M月d日（今日）", new Date(2026, 0, 3)), "26年1月3日（今日）");
    assert.equal(previewDateFormat("yyyy/MM/dd", new Date(2024, 1, 29)), "2024/02/29");
});

test("custom formats preserve literal characters, order, and stored opt-in defaults", () => {
    const custom = [" yy/M/d ", "yyyy年MM月dd日🗓"];
    assert.deepEqual(normalizeDateFormats(undefined), DEFAULT_DATE_FORMATS);
    assert.notEqual(normalizeDateFormats(undefined), DEFAULT_DATE_FORMATS);
    assert.deepEqual(normalizeDateFormats(custom), custom);
    assert.equal(validateDateFormats(custom), "");
    assert.equal(previewDateFormat(custom[0], new Date(2026, 0, 3)), " 26/1/3 ");
    assert.throws(() => normalizeDateFormats([42]));
    assert.throws(() => normalizeDateFormats(null));
});

test("invalid tokens, missing date tokens, empty rows and control characters cannot be saved", () => {
    for (const format of ["", "　 ", "今日", "2026/11/13", "yyy/M/d", "YYYY/MM/dd", "yyyy/MM/dd HH:mm", "yyyy\nd", "yyyy\td", "yyyy\rd", "yyyy\0d", "yyyy\u0085d", "yyyy\u2028d", "yyyy\u2029d"]) {
        assert.match(validateDateFormats(["yyyyMMdd", format]), /^2行目:/, JSON.stringify(format));
        assert.equal(previewDateFormat(format, new Date()), "");
    }
    assert.ok(validateDateFormats([]));
});

test("format limits count Unicode scalars consistently with native settings", () => {
    const exact = `d${"🗓".repeat(MAX_DATE_FORMAT_CHARS - 1)}`;
    assert.equal(validateDateFormats([exact]), "");
    assert.match(validateDateFormats([`${exact}日`]), /64/);
    assert.equal(validateDateFormats(Array(MAX_DATE_FORMATS).fill("d")), "");
    assert.match(validateDateFormats(Array(MAX_DATE_FORMATS + 1).fill("d")), /10/);
});
