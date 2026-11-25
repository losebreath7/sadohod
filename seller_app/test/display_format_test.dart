import 'package:flutter_test/flutter_test.dart';
import 'package:sadohod_shared_core/display_format.dart';
void main(){
 test('all amounts have one approximation prefix including zero',(){expect(approximateRubles(0),'≈ 0 ₽');expect(approximateRubles(3890),'≈ 3 890 ₽');expect(approximateRubles(100000000),'≈ 100 000 000 ₽');});
 test('contact display keeps public nicknames and Russian WhatsApp format',(){expect(contactLineDisplay('https://t.me/nickname'),'тг: nickname');expect(contactLineDisplay('https://vk.com/nickname'),'вк: nickname');expect(contactLineDisplay('https://wa.me/79979969995'),'whatsapp: 89979969995');});
 test('display and deep links are separate',(){expect(contactLineTarget('тг: nickname').toString(),'https://t.me/nickname');expect(contactLineTarget('вк: nickname').toString(),'https://vk.com/nickname');expect(contactLineTarget('whatsapp: 89979969995').toString(),'https://wa.me/79979969995');});
}
