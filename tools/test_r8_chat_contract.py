"""Static release checks where Flutter SDK is unavailable. Not a widget test."""
import unittest
from pathlib import Path
from PIL import Image
from collections import Counter

ROOT=Path(__file__).resolve().parents[1]


class R8Contract(unittest.TestCase):
    def test_single_chat_presentation_for_four_routes(self):
        shared=(ROOT/'shared/flutter_core/lib/chat_widgets.dart').read_text()
        buyer=(ROOT/'buyer_app/lib/features/account/profile_features.dart').read_text()
        seller=(ROOT/'seller_app/lib/seller_telegram_chat.dart').read_text()
        self.assertIn('class SadohodChatConversation',shared)
        self.assertIn('class SadohodChatHeader',shared)
        self.assertIn('minLines: 1',shared)
        self.assertIn('maxLines: 5',shared)
        self.assertNotIn('WidgetSpan(',shared)
        self.assertIn('const SizedBox(height: 4)',shared)
        self.assertIn('textAlignVertical: TextAlignVertical.center',shared)
        self.assertIn('contentPadding: EdgeInsets.symmetric(vertical: 12)',shared)
        self.assertIn('alignment: Alignment.centerRight, child: _meta()',shared)
        self.assertIn('final width = desiredWidth.clamp(82.0, maximum).toDouble();',shared)
        self.assertNotIn('Positioned(right:',shared)
        self.assertIn('SadohodChatConversation(',buyer)
        self.assertIn('SadohodChatConversation(',seller)
        self.assertIn("kind == 'support'",buyer)
        self.assertIn("kind == 'support'",seller)
        self.assertIn('bottom: keyboardVisible ? 8 : 17',shared)

    def test_same_phone_shell_for_two_apps(self):
        for app in ('buyer_app/lib/app/app.dart','seller_app/lib/main.dart'):
            self.assertIn('SadohodDevicePreviewShell', (ROOT/app).read_text())
        self.assertIn('deviceHeight = 874.0', (ROOT/'shared/flutter_core/lib/device_preview_shell.dart').read_text())
        self.assertIn('if (!kIsWeb || viewport.width < 650)', (ROOT/'shared/flutter_core/lib/device_preview_shell.dart').read_text())

    def test_seller_pattern_colors(self):
        expected={'support':(204,183,180),'cooperation':(214,222,228)}
        for name,color in expected.items():
            pixels=Counter(Image.open(ROOT/f'seller_app/assets/figma/seller_{name}_pattern.png').convert('RGB').getdata())
            self.assertIn(color,pixels)
            self.assertGreater(pixels[color],10000)

if __name__=='__main__':
    unittest.main()
