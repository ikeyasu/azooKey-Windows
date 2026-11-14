export declare const DEFAULT_DATE_FORMATS: string[];
export declare const MAX_DATE_FORMATS: number;
export declare const MAX_DATE_FORMAT_CHARS: number;
export declare const normalizeDateFormats: (value: unknown) => string[];
export declare const validateDateFormats: (formats: string[]) => string;
export declare const previewDateFormat: (format: string, date: Date) => string;
