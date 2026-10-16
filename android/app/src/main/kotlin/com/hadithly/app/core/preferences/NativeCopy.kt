package com.hadithly.app.core.preferences

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.core.text.BidiFormatter
import com.hadithly.app.R

@Composable
fun nativeText(source: String, vararg arguments: Any): String =
    androidx.compose.ui.platform.LocalResources.current.nativeText(source, *arguments)

fun Context.nativeText(source: String, vararg arguments: Any): String = resources.nativeText(source, *arguments)

private fun android.content.res.Resources.nativeText(source: String, vararg arguments: Any): String {
    val resource = nativeCopyResource(source) ?: return source
    if (arguments.isEmpty()) return getString(resource)
    val locale = configuration.locales[0]
    val bidi = BidiFormatter.getInstance(locale)
    return getString(resource, *arguments.map { bidi.unicodeWrap(it.toString()) }.toTypedArray())
}

private fun nativeCopyResource(source: String): Int? = when (source) {
    "Describe a meaning, wording, or attribution concern. Reports are private and are not votes or ratings." -> R.string.native_004e9ce2b80f
    "Save username" -> R.string.native_00cb857374a6
    "Start a new suggestion" -> R.string.native_03c47f10db6d
    "Export your profile, preferences, Saved items, folders, reading progress, and your own contributions as JSON." -> R.string.native_099cd53b4147
    "Add one to three source links or files. Evidence stays private while checked." -> R.string.native_0ab48e787f8a
    "Close settings" -> R.string.native_0ccfef828950
    "Sign in from Settings to suggest a translation with evidence." -> R.string.native_102b5d6815d5
    "Done" -> R.string.native_11a6767d5674
    "AI translation…" -> R.string.native_12d8c4057f56
    "Save" -> R.string.native_1509f561f241
    "The private files were removed before processing. You can start a new suggestion." -> R.string.native_161faa795821
    "EDIT" -> R.string.native_18a0c098c7fb
    "Cancel" -> R.string.native_19766ed6ccb2
    "Bookmark" -> R.string.native_1bac4007880b
    "Private reason" -> R.string.native_1ddc2d9a1a21
    "Avatar is set by your sign-in method." -> R.string.native_21d749165449
    "VOLUMES" -> R.string.native_258de606097f
    "Share" -> R.string.native_29887a5ff984
    "Processing evidence. Your suggestion stays private and has not been reviewed or published." -> R.string.native_2f4412f8bb6a
    "Send me a hadith every day" -> R.string.native_30b8238e7f5b
    "Forgot password?" -> R.string.native_30c1d8d3e912
    "Cancel upload" -> R.string.native_326d9c957d5a
    "Time" -> R.string.native_33b93476cf59
    "Could not open this collection" -> R.string.native_3740fd6cbdff
    "Clear temporary cache" -> R.string.native_3bad88c3376c
    "Suggest translation" -> R.string.native_3c707d34de67
    "Sign in to receive the daily hadith on this device." -> R.string.native_3ea7835d6d78
    "Contents" -> R.string.native_437aea62a5bd
    "Delete draft" -> R.string.native_46495379257b
    "Text layers" -> R.string.native_4814c85aa23d
    "Page %1\$s" -> R.string.native_482a6cdaa409
    "The file contains only your portable data. You must be signed in; an expired session signs you in again first." -> R.string.native_483dc4ca0c62
    "Sign out" -> R.string.native_48f0d3d397d4
    "No %1\$s translation is available yet." -> R.string.native_49103f50966a
    "Search" -> R.string.native_49c266baaaa7
    "Reference: %1\$s" -> R.string.native_4dc42835fbc3
    "Hadithly Pro is active" -> R.string.native_4f543e452064
    "Remove and don't ask again" -> R.string.native_4fa960716706
    "Sign in to see your subscription. Purchases stay attached to your Hadithly account across devices." -> R.string.native_50deba1f29ea
    "Evidence expired" -> R.string.native_51da6060f286
    "No matches in Sunnah.now English text." -> R.string.native_540ec6e92d83
    "No English translation available yet." -> R.string.native_5457393ebfcc
    "Select again" -> R.string.native_5474755405da
    "OK" -> R.string.native_565339bc4d33
    "A quiet reader for the seven major hadith collections. Arabic text is licensed from its sources; AI translations are always labeled." -> R.string.native_58d330f27985
    "Opening %1\$s…" -> R.string.native_5a22ad9780f1
    "Account deletion failed" -> R.string.native_5d69219595e8
    "Close contents" -> R.string.native_5f8fefc620cb
    "AI translation unavailable · retry" -> R.string.native_61c2709f9d99
    "End of page" -> R.string.native_63624455a1b0
    "Usernames start with a letter and use letters, numbers, and underscores." -> R.string.native_657e34fbabb2
    "Report sent privately" -> R.string.native_6a77e7691626
    "Add image or PDF" -> R.string.native_6aeba22b0308
    "Passwords do not match." -> R.string.native_6c6e178ad2a8
    "Go" -> R.string.native_6cc8519b9158
    "Licenses" -> R.string.native_6d5d90047973
    "No eligible hadith is cached yet" -> R.string.native_6ef998ee12f7
    "First name" -> R.string.native_702ef921ed1d
    "At least one layer stays visible." -> R.string.native_709e31254bdd
    "Suggest a translation" -> R.string.native_71223a24948d
    "or" -> R.string.native_7175517a370b
    "At least one text layer stays visible." -> R.string.native_71c7158ec4ea
    "Settings" -> R.string.native_74a883a037bc
    "Back" -> R.string.native_76900f1bfd16
    "HTTPS source link" -> R.string.native_76a282009ba8
    "Bookmarks & Notes" -> R.string.native_77889b3bab7e
    "Create account" -> R.string.native_798ca2ce18bf
    "Last name" -> R.string.native_7b4888049459
    "Delete account and data" -> R.string.native_7b503321357a
    "Write a private note…" -> R.string.native_7d94fc6f0852
    "Close" -> R.string.native_7d9eb7acb13e
    "Open a collection in the Library and Today will prepare one from verified content." -> R.string.native_82095f5cb9a4
    "Evidence received; awaiting checks." -> R.string.native_82c66ec1be55
    "Choose location" -> R.string.native_83bbbb83cfbe
    "Pause" -> R.string.native_858e4ba7a29f
    "Today's hadith could not load" -> R.string.native_8809dd9048f8
    "How offline works" -> R.string.native_892ffa345a39
    "Page %1\$s of %2\$s" -> R.string.native_8b9ffadf4985
    "Sign in to export your synced data. Guest data never leaves this device." -> R.string.native_8ba1f434afb9
    "You can undo this action from the message at the top." -> R.string.native_8e3a83b3d254
    "Downloads: %1\$s · Free: %2\$s" -> R.string.native_8f6ca5461ed2
    "Manage subscription" -> R.string.native_9041c6aa2c3d
    "Active" -> R.string.native_92340695899b
    "Nothing saved here yet." -> R.string.native_9361eac22a4e
    "Retry" -> R.string.native_942087cc2d41
    "Include the collection and hadith number." -> R.string.native_9449e60a6bd1
    "Open device storage" -> R.string.native_96b3b31d45ab
    "Arabic type" -> R.string.native_96be15d18327
    "Evidence checks complete" -> R.string.native_98770753608c
    "Retry evidence" -> R.string.native_9c2816aadb36
    "Collections" -> R.string.native_9f9feade761d
    "Offline" -> R.string.native_a1794783aab7
    "Search is unavailable offline." -> R.string.native_a1a6ea9533fa
    "Bringing today's hadith…" -> R.string.native_a4194ff09706
    "Search English text" -> R.string.native_b01111be1821
    "Base Arabic files plus a translation pack for your language. Every file is checksummed and licensed before it activates. The previous copy stays readable until the replacement and your saved positions check out." -> R.string.native_b5a1c683ff49
    "Sunnah.now English text" -> R.string.native_b67dee925588
    "Save name" -> R.string.native_b7297226fd1f
    "Use a different email" -> R.string.native_b7337027ef1f
    "Withdraw suggestion" -> R.string.native_b7bd92f57552
    "Clearing never deletes bookmarks, favorites, notes, reading progress, or downloaded collections." -> R.string.native_b7d74756ff3b
    "Resend code" -> R.string.native_b97457409ab5
    "Your suggestion remains private. Withdraw it and submit different evidence if needed." -> R.string.native_b9c98d6ecdf1
    "Hadith number" -> R.string.native_bdd5c6b7f515
    "Hadithly ships versioned offline collections: a base Arabic dump plus translation packs, each checksummed and licensed. Downloads validate before activating and keep your Saved items and reading positions intact. Deleting a download removes files only — your bookmarks, notes, and positions stay." -> R.string.native_bf948705a783
    "Sign in" -> R.string.native_bfd402b2f6f3
    "Update" -> R.string.native_c1c1009d3f37
    "Searching…" -> R.string.native_c31723ab3302
    "Remove" -> R.string.native_c3812fc4acb8
    "Grounding citations" -> R.string.native_c4bbcbb7a6a7
    "Wi-Fi only" -> R.string.native_ca99bb9196aa
    "Sources" -> R.string.native_caf85b0888d7
    "Type above to search the English text." -> R.string.native_d0dc72eadb20
    "Resume" -> R.string.native_d640c7421da0
    "Download" -> R.string.native_d6eafe823591
    "Try again" -> R.string.native_d8b8392e2c54
    "Note" -> R.string.native_d8da2c49df39
    "See Hadithly's total device storage from the system settings page." -> R.string.native_d96ad3ca286c
    "Sign in with a code instead" -> R.string.native_d9a85e0a70d8
    "Name" -> R.string.native_dcd1d5223f73
    "Remove saved item?" -> R.string.native_dddd7b14feda
    "%1\$s pt" -> R.string.native_de60e9e3043d
    "Add link" -> R.string.native_dfe9ca4d0f96
    "Download translation" -> R.string.native_e05372bd9e28
    "Copy" -> R.string.native_e21f935f11d7
    "Username" -> R.string.native_e3b89e9d33f8
    "Reading as a guest" -> R.string.native_e820440bb043
    "Temporary cache" -> R.string.native_ec0c8dea1a19
    "Checking…" -> R.string.native_ec963ffc911b
    "Export your data?" -> R.string.native_ecdba5aa3ba4
    "Your data" -> R.string.native_ee5ef73aae18
    "Report translation" -> R.string.native_f038ae10080f
    "Offline collections" -> R.string.native_f5a77522b1ba
    "Everything you need to read works without an account. Sign in to carry your bookmarks, favorites, and notes across devices." -> R.string.native_fa8a45b3662d
    "Applies across the app. The reader previews each theme live." -> R.string.native_ff6c3270c09d
    "Loading…" -> R.string.native_ba3bbbe10d8b
    "Loading page" -> R.string.native_91bf928d3527
    "Loading reading progress" -> R.string.native_dacaf10d67cb
    "Loading saved items" -> R.string.native_ff5b3391a8bb
    "Saved items could not load" -> R.string.native_5499da335be2
    "Loading subscription" -> R.string.native_af0a04c700a8
    "Subscription details could not load" -> R.string.native_6333ae18362e
    "Reader appearance" -> R.string.native_b226874c014f
    "Text size" -> R.string.native_d68761cc1eb2
    "Preview" -> R.string.native_324b134f57c7
    "Automatic translation" -> R.string.native_2981c4cfc618
    "Translate missing text automatically, within your allowance. Turn off to translate on request." -> R.string.native_5423d44a5cf5
    "Touch and hold a hadith to bookmark, add a note or share." -> R.string.native_fa05769818e1
    "Dismiss hint" -> R.string.native_279166910494
    "Sync bookmarks and notes across devices." -> R.string.native_9ad22124e012
    "Translation sources" -> R.string.native_43b0446666d2
    else -> null
}
