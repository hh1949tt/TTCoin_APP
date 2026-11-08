import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class TTCoinApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Watch App 返回 [View, Delegate] 二元组，Delegate 负责按键：
    //   Start → 设置菜单，Up/Down → 手动翻页，Back → 退出（系统默认）
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new TTCoinView();

        return [view, new TTCoinDelegate(view)];
    }
}
