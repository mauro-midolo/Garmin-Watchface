using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class FenixWatchfaceApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new FenixWatchfaceView() ];
    }

    function onSettingsChanged() {
        Ui.requestUpdate();
    }
}
