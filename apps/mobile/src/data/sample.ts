export const hadiths = [
  {
    id: "b1-1",
    collectionSlug: "bukhari",
    ref: "Bukhari 1:1",
    shortRef: "1:1",
    reference: "Sahih al-Bukhari · Book 1 · Hadith 1",
    topic: "Faith",
    book: "Revelation",
    arabic:
      "إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ، وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى، فَمَنْ كَانَتْ هِجْرَتُهُ إِلَى اللَّهِ وَرَسُولِهِ فَهِجْرَتُهُ إِلَى اللَّهِ وَرَسُولِهِ، وَمَنْ كَانَتْ هِجْرَتُهُ لِدُنْيَا يُصِيبُهَا أَوِ امْرَأَةٍ يَنْكِحُهَا فَهِجْرَتُهُ إِلَى مَا هَاجَرَ إِلَيْهِ.",
    english:
      "Actions are but by intention, and every man shall have only that which he intended. So whoever's migration was for Allah and His Messenger, his migration is for Allah and His Messenger.",
    translation:
      "Поистине, дела оцениваются только по намерениям, и каждому человеку достанется лишь то, что он намеревался обрести.",
    sourceLabel: "Gemini AI",
    grade: "Sahih",
    ratingPercent: 94,
    votes: 32,
    narrator: "Umar ibn al-Khattab (ra)"
  },
  {
    id: "b2-8",
    collectionSlug: "bukhari",
    ref: "Bukhari 2:8",
    shortRef: "2:8",
    reference: "Sahih al-Bukhari · Book 2 · Hadith 8",
    topic: "Faith",
    book: "Belief",
    arabic:
      "بُنِيَ الْإِسْلَامُ عَلَى خَمْسٍ: شَهَادَةِ أَنْ لَا إِلَهَ إِلَّا اللَّهُ وَأَنَّ مُحَمَّدًا رَسُولُ اللَّهِ، وَإِقَامِ الصَّلَاةِ، وَإِيتَاءِ الزَّكَاةِ، وَالْحَجِّ، وَصَوْمِ رَمَضَانَ.",
    english:
      "Islam is built upon five: the testimony that none has the right to be worshipped except Allah and that Muhammad is the Messenger of Allah, the establishment of prayer, zakah, pilgrimage, and Ramadan.",
    translation:
      "Ислам основан на пяти столпах: свидетельстве, что нет божества, кроме Аллаха, и что Мухаммад - Посланник Аллаха; совершении молитвы; выплате закята; паломничестве; и посте в месяц Рамадан.",
    sourceLabel: "Community",
    grade: "Sahih",
    ratingPercent: 96,
    votes: 184,
    narrator: "Ibn Umar (ra)"
  },
  {
    id: "m-15",
    collectionSlug: "muslim",
    ref: "Muslim 15",
    shortRef: "15",
    reference: "Sahih Muslim · Book 1 · Hadith 15",
    topic: "Character",
    book: "Faith",
    arabic:
      "مَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيَقُلْ خَيْرًا أَوْ لِيَصْمُتْ، وَمَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيُكْرِمْ جَارَهُ، وَمَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيُكْرِمْ ضَيْفَهُ.",
    english:
      "Whoever believes in Allah and the Last Day, let him speak good or remain silent. Whoever believes in Allah and the Last Day, let him honour his neighbour and guest.",
    translation:
      "Тот, кто верит в Аллаха и Последний день, пусть говорит благое или молчит. Тот, кто верит в Аллаха и Последний день, пусть оказывает почет соседу и гостю.",
    sourceLabel: "Gemini AI",
    grade: "Sahih",
    ratingPercent: null,
    votes: 3,
    narrator: "Abu Hurayra (ra)"
  },
  {
    id: "tirm-2517",
    collectionSlug: "tirmidhi",
    ref: "Tirmidhi 2517",
    shortRef: "2517",
    reference: "Jami at-Tirmidhi · Hadith 2517",
    topic: "Character",
    book: "Faith",
    arabic: "دَعْ مَا يَرِيبُكَ إِلَى مَا لَا يَرِيبُكَ.",
    english: "Leave that which makes you doubt for that which does not make you doubt.",
    translation: "Оставь то, что вызывает у тебя сомнение, ради того, что сомнения не вызывает.",
    sourceLabel: "Official EN",
    grade: "Hasan Sahih",
    ratingPercent: null,
    votes: 0,
    narrator: "al-Hasan ibn Ali (ra)"
  }
];

export const dailyHadith = hadiths[0];

export const collections = [
  { slug: "bukhari", title: "Sahih al-Bukhari", en: "Sahih al-Bukhari", arabic: "صحيح البخاري", ar: "صحيح البخاري", count: 7563, coverage: 12, grade: "Sahih" },
  { slug: "muslim", title: "Sahih Muslim", en: "Sahih Muslim", arabic: "صحيح مسلم", ar: "صحيح مسلم", count: 7470, coverage: 18, grade: "Sahih" },
  { slug: "abu-dawood", title: "Sunan Abu Dawud", en: "Sunan Abu Dawud", arabic: "سنن أبي داود", ar: "سنن أبي داود", count: 5274, coverage: 6, grade: "Sunan" },
  { slug: "tirmidhi", title: "Jami at-Tirmidhi", en: "Jami at-Tirmidhi", arabic: "جامع الترمذي", ar: "جامع الترمذي", count: 3956, coverage: 4, grade: "Sunan" },
  { slug: "nasai", title: "Sunan an-Nasai", en: "Sunan an-Nasai", arabic: "سنن النسائي", ar: "سنن النسائي", count: 5761, coverage: 2, grade: "Sunan" },
  { slug: "ibn-majah", title: "Sunan Ibn Majah", en: "Sunan Ibn Majah", arabic: "سنن ابن ماجه", ar: "سنن ابن ماجه", count: 4341, coverage: 1, grade: "Sunan" },
  { slug: "malik", title: "Muwatta Malik", en: "Muwatta Malik", arabic: "موطأ مالك", ar: "موطأ مالك", count: 1851, coverage: 0, grade: "Sahih" },
  { slug: "nawawi40", title: "Forty Hadith of an-Nawawi", en: "Forty Hadith of an-Nawawi", arabic: "الأربعون النووية", ar: "الأربعون النووية", count: 42, coverage: 88, grade: "Sahih" }
];

export const languages = [
  { code: "en", title: "English", native: "English", coverage: 100, status: "Official", flag: "US" },
  { code: "ar", title: "Arabic", native: "العربية", coverage: 100, status: "Source", flag: "SA" },
  { code: "kk", title: "Kazakh", native: "Қазақша", coverage: 12, status: "community", flag: "KZ" },
  { code: "ru", title: "Russian", native: "Русский", coverage: 38, status: "community", flag: "RU" },
  { code: "tr", title: "Turkish", native: "Türkçe", coverage: 22, status: "community", flag: "TR" },
  { code: "uz", title: "Uzbek", native: "O'zbekcha", coverage: 9, status: "community", flag: "UZ" },
  { code: "id", title: "Indonesian", native: "Bahasa Indonesia", coverage: 41, status: "community", flag: "ID" },
  { code: "ur", title: "Urdu", native: "اُردُو", coverage: 28, status: "community", flag: "PK" }
];

export const topics = [
  { label: "Faith", color: "#4B68D8" },
  { label: "Prayer", color: "#7C4FD8" },
  { label: "Character", color: "#B45A43" },
  { label: "Knowledge", color: "#1688A8" },
  { label: "Fasting", color: "#B8893B" },
  { label: "Family", color: "#C64F7C" },
  { label: "Charity", color: "#168A4A" },
  { label: "Manners", color: "#B14FB7" }
];

export const bookRows = [
  ["Revelation", 7, "الوحي", 100],
  ["Belief", 51, "الإيمان", 11],
  ["Knowledge", 76, "العلم", 88],
  ["Ablutions", 113, "الوضوء", 22],
  ["Ghusl", 41, "الغسل", 6],
  ["Menses", 31, "الحيض", 14],
  ["Tayammum", 16, "التيمم", 0]
] as const;

export const readerHadiths = hadiths;
