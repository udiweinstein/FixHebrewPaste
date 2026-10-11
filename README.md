# Hebrew RTL Fix

<div dir="rtl">

תוסף לדפדפן שמיישר לימין טקסט בעברית בכלי AI כמו ChatGPT, Gemini ו-Claude, וגם בכל אתר אחר.

![לפני ואחרי](screenshot.png)

*מימין: לפני. משמאל: אחרי.*

## הבעיה

כששואלים כלי AI שאלה בעברית, התשובה מוצגת לעיתים קרובות מיושרת לשמאל. נקודות התבליט מופיעות בצד הלא נכון, והפיסוק קופץ לתחילת השורה. גם כשמבקשים מה-AI לתקן, היישור חוזר לשמאל.

## מה התוסף עושה

- **מזהה עברית אוטומטית.** כל פסקה, כותרת, פריט ברשימה או תא בטבלה שלפחות 30% מהאותיות בו בעבריות מיושר לימין.
- **עובד בזמן אמת.** גם תשובה שנכתבת תוך כדי מתיישרת מיד. אם האתר מרנדר את הטקסט מחדש, התוסף מיישר אותו שוב.
- **מסדר רשימות וציטוטים.** התבליטים, המספור והקו של הציטוט עוברים לצד ימין.
- **משאיר קוד משמאל לימין.** בלוקים של קוד לא משתנים.
- **מטפל בשורות קצרות באנגלית.** שורות כמו `TL;DR:` מקבלות את הכיוון של הפסקאות שלידן.
- **מכבים בלחיצה.** אפשר לכבות את התוסף לגמרי או רק באתר מסוים, והשינוי חל מיד.

התוסף עובד בכל דפדפן מבוסס Chromium, כלומר Edge, Chrome ו-Brave, ב-Mac וב-Windows.

## התקנה

התוסף לא נמצא בחנות התוספים, ולכן מתקינים אותו ידנית. זה לוקח פחות מדקה.

### שלב 1: הורדה

בדף הזה לוחצים על הכפתור הירוק **Code** ואז על **Download ZIP**. אפשר גם להוריד את הקובץ מ-[Releases](../../releases), אם קיים שם.

### שלב 2: חילוץ

- **Mac:** לחיצה כפולה על קובץ ה-ZIP ב-Finder.
- **Windows:** קליק ימני על הקובץ, **Extract All** (חלץ הכל).

שמרו את התיקייה במקום קבוע, למשל בתיקיית המסמכים. הדפדפן טוען את התוסף מהתיקייה הזו, ולכן אסור למחוק אותה.

### שלב 3: טעינה לדפדפן

1. פותחים את דף התוספים:
   - **Edge:** `edge://extensions`
   - **Chrome:** `chrome://extensions`
   - **Brave:** `brave://extensions`
2. מפעילים את **Developer mode** (מצב מפתח). ב-Edge המתג נמצא בתפריט הצד, ובכרום בפינה הימנית העליונה.
3. לוחצים על **Load unpacked** (טען לא ארוז).
4. בוחרים את התיקייה שמכילה את הקובץ `manifest.json`.
5. מרעננים טאבים שהיו פתוחים לפני ההתקנה.

> **שימו לב:** ב-Windows החילוץ יוצר לפעמים תיקייה בתוך תיקייה עם אותו שם. אם מופיעה שגיאה שהקובץ `manifest.json` לא נמצא, כנסו רמה אחת פנימה ובחרו את התיקייה שוב.

כדאי להצמיד את התוסף לסרגל הכלים דרך סמל הפאזל 🧩 שליד שורת הכתובת.

## שימוש

התוסף פועל אוטומטית. לחיצה על האייקון שלו פותחת חלון עם שתי אפשרויות:

- **פעיל בכל האתרים:** מתג כללי להפעלה וכיבוי.
- **פעיל באתר הזה:** כיבוי רק באתר הנוכחי, למשל אם התוסף משנה בו משהו שלא רציתם.

## עדכון

מורידים את הגרסה החדשה, מחליפים את הקבצים בתיקייה, ולוחצים על כפתור הרענון ↻ של התוסף בדף התוספים.

## פרטיות

התוסף לא אוסף מידע ולא שולח שום דבר לשום מקום. כל העבודה נעשית בדף עצמו, והדבר היחיד שנשמר הוא ההגדרות שלכם. הקוד פתוח וקצר, ואפשר לקרוא את כולו.

## בעיות והצעות

מצאתם אתר שבו היישור לא עובד, או אלמנט שהתהפך בטעות? פתחו [Issue](../../issues) וצרפו צילום מסך.

</div>

---

## English

A browser extension that right-aligns Hebrew text in AI chat tools (ChatGPT, Gemini, Claude) and on any other website.

**Features**
- Detects Hebrew-dominant paragraphs, headings, list items and table cells (≥30% Hebrew letters) and sets them to RTL.
- Works on streaming responses and re-applies when the page re-renders.
- Moves list bullets and blockquote borders to the right; keeps code blocks LTR.
- Short Latin-only lines (e.g. `TL;DR:`) follow the direction of neighbouring paragraphs.
- Toggle globally or per site from the toolbar popup.
- No data collection, no network requests.

**Install (Edge / Chrome / Brave, macOS or Windows)**
1. Download this repository as ZIP and extract it to a permanent location.
2. Open `edge://extensions` (or `chrome://extensions`).
3. Enable **Developer mode**.
4. Click **Load unpacked** and select the folder containing `manifest.json`.
5. Reload any tabs that were already open.

## License

MIT
