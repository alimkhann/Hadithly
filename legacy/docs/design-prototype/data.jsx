// Sample hadith data for Hadithly prototype
// Real hadith text in Arabic + English; translations in Russian/Kazakh placeholders

const HADITHS = [
  {
    id: 'b1-1',
    ref: 'Bukhari 1:1',
    shortRef: '1:1',
    topic: 'Faith',
    refDisplay: 'Sahih al-Bukhari · Book 1 · Hadith 1',
    book: 'Revelation',
    arabic: 'إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ، وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى، فَمَنْ كَانَتْ هِجْرَتُهُ إِلَى اللَّهِ وَرَسُولِهِ فَهِجْرَتُهُ إِلَى اللَّهِ وَرَسُولِهِ، وَمَنْ كَانَتْ هِجْرَتُهُ لِدُنْيَا يُصِيبُهَا أَوِ امْرَأَةٍ يَنْكِحُهَا فَهِجْرَتُهُ إِلَى مَا هَاجَرَ إِلَيْهِ.',
    english: 'Actions are but by intention, and every man shall have only that which he intended. So whoever\u2019s migration was for Allah and His Messenger, his migration is for Allah and His Messenger. And whoever\u2019s migration was for some worldly gain or to marry a woman, his migration is for what he migrated for.',
    russian: 'Поистине, дела оцениваются только по намерениям, и каждому человеку достанется лишь то, что он намеревался обрести. Так, переселявшийся ради Аллаха и Его Посланника переселится к Аллаху и Его Посланнику, а переселявшийся ради чего-нибудь мирского или ради женщины, на которой он хотел жениться, переселится лишь к тому, к чему переселялся.',
    grade: 'Sahih',
    gradeApplies: 'hadith',
    translationSource: 'Gemini AI',
    translationKind: 'gemini',
    ratingPercent: 94,
    votes: 32,
    narrator: 'Umar ibn al-Khattab (ra)',
  },
  {
    id: 'b2-8',
    ref: 'Bukhari 2:8',
    shortRef: '2:8',
    topic: 'Faith',
    refDisplay: 'Sahih al-Bukhari · Book 2 · Hadith 8',
    book: 'Belief',
    arabic: 'بُنِيَ الْإِسْلَامُ عَلَى خَمْسٍ: شَهَادَةِ أَنْ لَا إِلَهَ إِلَّا اللَّهُ وَأَنَّ مُحَمَّدًا رَسُولُ اللَّهِ، وَإِقَامِ الصَّلَاةِ، وَإِيتَاءِ الزَّكَاةِ، وَالْحَجِّ، وَصَوْمِ رَمَضَانَ.',
    english: 'Islam is built upon five: the testimony that none has the right to be worshipped except Allah and that Muhammad is the Messenger of Allah, the establishment of prayer, the giving of zakah, the pilgrimage, and the fast of Ramadan.',
    russian: 'Ислам основан на пяти столпах: свидетельстве, что нет божества, кроме Аллаха, и что Мухаммад — Посланник Аллаха; совершении молитвы; выплате закята; паломничестве; и посте в месяц Рамадан.',
    grade: 'Sahih',
    gradeApplies: 'hadith',
    translationSource: 'Community',
    translationKind: 'community',
    ratingPercent: 96,
    votes: 184,
    narrator: 'Ibn \u02BBUmar (ra)',
  },
  {
    id: 'm-15',
    ref: 'Muslim 15',
    shortRef: '15',
    topic: 'Character',
    refDisplay: 'Sahih Muslim · Book 1 · Hadith 15',
    book: 'Faith',
    arabic: 'مَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيَقُلْ خَيْرًا أَوْ لِيَصْمُتْ، وَمَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيُكْرِمْ جَارَهُ، وَمَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيُكْرِمْ ضَيْفَهُ.',
    english: 'Whoever believes in Allah and the Last Day, let him speak good or remain silent. Whoever believes in Allah and the Last Day, let him honour his neighbour. Whoever believes in Allah and the Last Day, let him honour his guest.',
    russian: 'Тот, кто верит в Аллаха и Последний день, пусть говорит благое или молчит. Тот, кто верит в Аллаха и Последний день, пусть оказывает почёт своему соседу. Тот, кто верит в Аллаха и Последний день, пусть оказывает почёт своему гостю.',
    grade: 'Sahih',
    gradeApplies: 'hadith',
    translationSource: 'Gemini AI',
    translationKind: 'gemini',
    ratingPercent: null,
    votes: 3,
    narrator: 'Abu Hurayra (ra)',
  },
  {
    id: 'tirm-2517',
    ref: 'Tirmidhi 2517',
    shortRef: '2517',
    topic: 'Character',
    refDisplay: 'Jami\u02BB at-Tirmidhi · Hadith 2517',
    book: 'Faith',
    arabic: 'دَعْ مَا يَرِيبُكَ إِلَى مَا لَا يَرِيبُكَ.',
    english: 'Leave that which makes you doubt for that which does not make you doubt.',
    russian: 'Оставь то, что вызывает у тебя сомнение, ради того, что сомнения не вызывает.',
    grade: 'Hasan Sahih',
    gradeApplies: 'hadith',
    translationSource: 'Official EN',
    translationKind: 'official',
    ratingPercent: null,
    votes: 0,
    narrator: 'al-Hasan ibn \u02BBAli (ra)',
  },
];

const COLLECTIONS = [
  { slug: 'bukhari', en: 'Sahih al-Bukhari', ar: 'صحيح البخاري', count: 7563, grade: 'Sahih', coverage: 12, color: '#0F766E' },
  { slug: 'muslim', en: 'Sahih Muslim', ar: 'صحيح مسلم', count: 7470, grade: 'Sahih', coverage: 18, color: '#0F766E' },
  { slug: 'abudawud', en: 'Sunan Abu Dawud', ar: 'سنن أبي داود', count: 5274, grade: 'Sunan', coverage: 6, color: '#7C5C2E' },
  { slug: 'tirmidhi', en: 'Jami\u02BB at-Tirmidhi', ar: 'جامع الترمذي', count: 3956, grade: 'Sunan', coverage: 4, color: '#7C5C2E' },
  { slug: 'nasai', en: 'Sunan an-Nasa\u02BCi', ar: 'سنن النسائي', count: 5761, grade: 'Sunan', coverage: 2, color: '#7C5C2E' },
  { slug: 'ibnmajah', en: 'Sunan Ibn Majah', ar: 'سنن ابن ماجه', count: 4341, grade: 'Sunan', coverage: 1, color: '#7C5C2E' },
  { slug: 'malik', en: 'Muwatta Malik', ar: 'موطأ مالك', count: 1851, grade: 'Sahih', coverage: 0, color: '#0F766E' },
  { slug: 'nawawi40', en: 'Forty Hadith of an-Nawawi', ar: 'الأربعون النووية', count: 42, grade: 'Sahih', coverage: 88, color: '#B8893B' },
];

const LANGUAGES = [
  { code: 'en', en: 'English', native: 'English', coverage: 100, status: 'Official', flag: '🇺🇸' },
  { code: 'ar', en: 'Arabic', native: 'العربية', coverage: 100, status: 'Source', flag: '🇸🇦' },
  { code: 'kk', en: 'Kazakh', native: 'Қазақша', coverage: 12, status: 'community', ai: true, flag: '🇰🇿' },
  { code: 'ru', en: 'Russian', native: 'Русский', coverage: 38, status: 'community', ai: true, flag: '🇷🇺' },
  { code: 'tr', en: 'Turkish', native: 'Türkçe', coverage: 22, status: 'community', ai: true, flag: '🇹🇷' },
  { code: 'uz', en: 'Uzbek', native: 'O\u02BBzbekcha', coverage: 9, status: 'community', ai: true, flag: '🇺🇿' },
  { code: 'id', en: 'Indonesian', native: 'Bahasa Indonesia', coverage: 41, status: 'community', ai: true, flag: '🇮🇩' },
  { code: 'ur', en: 'Urdu', native: 'اُردُو', coverage: 28, status: 'community', ai: true, flag: '🇵🇰' },
  { code: 'de', en: 'German', native: 'Deutsch', coverage: 14, status: 'community', ai: true, flag: '🇩🇪' },
  { code: 'fr', en: 'French', native: 'Français', coverage: 19, status: 'community', ai: true, flag: '🇫🇷' },
  { code: 'ms', en: 'Malay', native: 'Bahasa Melayu', coverage: 8, status: 'community', ai: true, flag: '🇲🇾' },
];

const TOPICS = ['Faith', 'Prayer', 'Character', 'Knowledge', 'Fasting', 'Family', 'Charity', 'Manners'];

// Per-topic accent colors — varied tints, intentionally NOT the brand green.
// Tuned for OKLCH harmony: same chroma/lightness, varied hue.
const TOPIC_COLORS = {
  'Faith':     'oklch(0.62 0.14 250)',   // blue
  'Prayer':    'oklch(0.62 0.14 290)',   // violet
  'Character': 'oklch(0.62 0.14 30)',    // terracotta
  'Knowledge': 'oklch(0.62 0.14 210)',   // cyan
  'Fasting':   'oklch(0.62 0.14 80)',    // amber
  'Family':    'oklch(0.62 0.14 350)',   // rose
  'Charity':   'oklch(0.62 0.14 145)',   // moss
  'Manners':   'oklch(0.62 0.14 320)',   // magenta
};

Object.assign(window, { HADITHS, COLLECTIONS, LANGUAGES, TOPICS, TOPIC_COLORS });
