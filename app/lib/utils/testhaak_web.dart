import 'dart:convert';
import 'dart:js_interop';

@JS('homemaps')
external set _stand(JSString waarde);

/// Voor de browsertoetsen (ci/e2e/app_browser.py): de stand van de app als
/// JSON op `window.homemaps`. Alleen met `?simulatie=`; zie KaartScreen.
void publiceerTestStand(Map<String, Object?> stand) =>
    _stand = jsonEncode(stand).toJS;
