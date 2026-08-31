import unittest

from automation.source_visuals import candidates_from_html


class SourceVisualTests(unittest.TestCase):
    def test_prefers_open_graph_source_visual(self) -> None:
        html = '''
        <html><head>
          <meta property="og:image" content="/media/release-preview.jpg">
          <meta name="twitter:image" content="https://cdn.example.com/news-cover.png">
        </head><body>
          <img src="/assets/favicon.png" alt="logo">
          <img src="/images/feature-screenshot.webp" alt="Feature screenshot">
        </body></html>
        '''
        candidates = candidates_from_html("https://example.com/news/release", html)
        self.assertTrue(candidates)
        self.assertEqual(candidates[0].image_url, "https://example.com/media/release-preview.jpg")
        urls = {item.image_url for item in candidates}
        self.assertIn("https://example.com/images/feature-screenshot.webp", urls)
        self.assertNotIn("https://example.com/assets/favicon.png", urls)

    def test_rejects_tracking_and_profile_art(self) -> None:
        html = '''
        <html><body>
          <img src="https://example.com/tracking-pixel.gif">
          <img src="https://example.com/user-avatar.png">
          <img src="https://example.com/screenshots/demo.png" alt="Demo screenshot">
        </body></html>
        '''
        candidates = candidates_from_html("https://example.com/post", html)
        self.assertEqual([item.image_url for item in candidates], ["https://example.com/screenshots/demo.png"])


if __name__ == "__main__":
    unittest.main()
