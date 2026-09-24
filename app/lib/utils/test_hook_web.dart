import 'dart:convert';
import 'dart:js_interop';

@JS('homemaps')
external set _status(JSString value);

/// For the browser tests (ci/e2e/app_browser.py): the app's state as JSON on
/// `window.homemaps`. Only with `?simulate=`; see MapScreen.
void publishTestState(Map<String, Object?> status) =>
    _status = jsonEncode(status).toJS;
