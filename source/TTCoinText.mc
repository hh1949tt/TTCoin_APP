import Toybox.Lang;
import Toybox.WatchUi;

// ======================================================================
// 界面文案取用入口
//
// 文案不写在代码里，统一放资源表：
//   resources/strings/strings.xml        英文（基础语言，任何未翻译语言都落这里）
//   resources-zhs/strings/strings.xml    简体中文
//
// 为什么必须这样做：Instinct 2X 有两个固件 SKU —— 国际版
// （006-B4394-00）只带 Roboto，没有中文字形，硬编码的中文会画成方块；
// 中文版带 Noto Sans SC。文案进了资源表，系统语言是 zhs 就取中文、
// 其它语言取英文，同一个 .prg 两种固件都能正常显示。
//
// fallback 参数不是多余：万一资源 id 拼错、或某个语言的 xml 里漏了这条，
// loadResource 会返回 null，直接当字符串用会在 strict 模式下抛类型错误。
// ======================================================================

class TTCoinText {

    // 取一条资源字符串；取不到就用 fallback，保证永远返回非空 String
    // 形参类型必须是 Lang.ResourceId：Rez.Strings.Xxx 的类型是 ResourceId，不是 Symbol
    static function get(id as Lang.ResourceId, fallback as Lang.String) as Lang.String {

        var value = WatchUi.loadResource(id);

        if (value instanceof Lang.String) {

            var text = value as Lang.String;

            if (text.length() > 0) {
                return text;
            }
        }

        return fallback;
    }
}
