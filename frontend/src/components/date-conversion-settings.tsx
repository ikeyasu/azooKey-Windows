import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { SettingsRow, SettingsSection } from "@/components/settings-section";
import { UnsavedChangesGuard } from "@/components/unsaved-changes-guard";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { saveConfigWithToast } from "@/lib/config";
import { normalizeDateFormats, previewDateFormat, validateDateFormats } from "@/lib/date-formats.js";

export function DateConversionSettings({ enabled, formats, onEnabledChange, onFormatsSaved }: {
    enabled: boolean;
    formats: string[];
    onEnabledChange: (enabled: boolean) => Promise<void>;
    onFormatsSaved: (formats: string[]) => void;
}) {
    const persistedText = formats.join("\n");
    const [draft, setDraft] = useState(persistedText);
    const [busy, setBusy] = useState(false);
    const busyRef = useRef(false);
    const [today] = useState(() => new Date());
    const draftFormats = draft.split("\n");
    const validation = validateDateFormats(draftFormats);
    const dirty = draft !== persistedText;

    useEffect(() => { setDraft(persistedText); }, [persistedText]);

    const changeEnabled = async (next: boolean) => {
        if (busyRef.current) return;
        busyRef.current = true;
        setBusy(true);
        try { await onEnabledChange(next); }
        finally { busyRef.current = false; setBusy(false); }
    };
    const saveFormats = async () => {
        if (busyRef.current || !dirty) return;
        if (validation) {
            document.getElementById("date-formats")?.focus();
            return;
        }
        busyRef.current = true;
        setBusy(true);
        try {
            const data = await saveConfigWithToast((config) => {
                config.general = config.general ?? {};
                config.general.date_formats = draftFormats;
            }, "日付形式の保存に失敗しました");
            if (data) {
                const saved = normalizeDateFormats(data.general?.date_formats);
                onFormatsSaved(saved);
                setDraft(saved.join("\n"));
                toast("日付形式を保存しました");
            }
        } finally { busyRef.current = false; setBusy(false); }
    };

    return <SettingsSection title="日付の変換">
        <UnsavedChangesGuard dirty={dirty} />
        <SettingsRow label="今日の日付を候補に出す" description="「きょう」を変換すると、今日の日付を候補に追加します。" htmlFor="date-conversion">
            <Switch id="date-conversion" checked={enabled} disabled={busy} onCheckedChange={(next) => void changeEnabled(next)} />
        </SettingsRow>
        <SettingsRow label="日付形式" description="1行に1形式、上から候補順に指定します（最大10件・各64文字）。" htmlFor="date-formats">
            <div className="w-full space-y-3">
                <Textarea id="date-formats" rows={3} spellCheck={false} value={draft} disabled={busy}
                    aria-invalid={!!validation} aria-describedby="date-format-help date-format-error"
                    className="font-mono" onChange={(event) => setDraft(event.target.value)} />
                <p id="date-format-help" className="settings-description">yyyy: 西暦4桁 / yy: 西暦下2桁 / MM・dd: 月・日の2桁 / M・d: 月・日の数字。日本語や区切り文字も使えます。</p>
                {validation && <p id="date-format-error" role="alert" className="text-sm text-destructive">{validation}</p>}
                {!validation && <div className="space-y-1">
                    <p className="settings-description">今日の日付のプレビュー</p>
                    <ol aria-label="日付候補のプレビュー" className="list-inside list-decimal text-sm tabular-nums">
                        {draftFormats.map((format, index) => <li key={index} className="whitespace-pre-wrap break-all">{previewDateFormat(format, today)}</li>)}
                    </ol>
                </div>}
                <div className="settings-actions">
                    <Button disabled={busy || !dirty} onClick={() => void saveFormats()}>{busy ? "保存中…" : "日付形式を保存"}</Button>
                    {dirty && <span className="settings-description">未保存の変更</span>}
                </div>
            </div>
        </SettingsRow>
    </SettingsSection>;
}
