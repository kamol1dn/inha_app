package uz.inha.kamol1dn.inha_app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import kotlin.math.ceil

/**
 * Fraunces in a widget. A widget's layout is inflated by the launcher in a restricted context,
 * where TextView ignores font resources, so the words DESIGN.md gives to Fraunces (titles, the
 * room, course names, times, counts) are drawn here into a white mask bitmap and tinted with the
 * theme colour where they are shown. The font is read from the Flutter assets the app already
 * ships (assets/fonts), so nothing is bundled twice.
 */
enum class SerifFace(val file: String, val sizeSp: Float, val letterSpacing: Float = 0f) {
    HEADLINE("Fraunces-SemiBold.ttf", 19f),
    ROOM("FrauncesDisplay-SemiBold.ttf", 34f, -0.02f),
    COURSE_ITALIC("Fraunces-Italic.ttf", 16f),
    COURSE("Fraunces-SemiBold.ttf", 15f),
    NUMERAL("Fraunces-Regular.ttf", 15f),
    NUMERAL_SMALL("Fraunces-Regular.ttf", 12f),
}

object Serif {
    private const val MAX_PX = 2048
    private val typefaces = HashMap<String, Typeface?>()

    private fun typeface(context: Context, file: String): Typeface? = synchronized(typefaces) {
        typefaces.getOrPut(file) {
            try {
                Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/$file")
            } catch (_: RuntimeException) {
                null // falls back to the system serif
            }
        }
    }

    /**
     * [text] in [face], white on transparent, at most [maxWidthDp] wide (the last line that fits
     * is ellipsized) and only as wide as the text. Tabular figures, like the app.
     */
    fun bitmap(context: Context, text: String, face: SerifFace, maxWidthDp: Float, maxLines: Int = 1): Bitmap {
        val dm = context.resources.displayMetrics
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = typeface(context, face.file) ?: Typeface.SERIF
            textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, face.sizeSp, dm)
            letterSpacing = face.letterSpacing
            fontFeatureSettings = "tnum"
            color = Color.WHITE
        }
        val width = (maxWidthDp * dm.density).toInt().coerceIn(1, MAX_PX)
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .setMaxLines(maxLines)
            .setEllipsize(TextUtils.TruncateAt.END)
            .build()
        var widest = 0f
        for (i in 0 until layout.lineCount) widest = maxOf(widest, layout.getLineRight(i))
        val bitmap = Bitmap.createBitmap(
            ceil(widest).toInt().coerceIn(1, width),
            layout.height.coerceIn(1, MAX_PX),
            Bitmap.Config.ARGB_8888,
        )
        bitmap.density = dm.densityDpi
        layout.draw(Canvas(bitmap))
        return bitmap
    }
}
