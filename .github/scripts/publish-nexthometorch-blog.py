from pathlib import Path

required = {
    "next-home-torch-ios15-ios16.html": [
        "ca-pub-4770123899731214",
        "TechArticle",
        "NextHomeTorch_1.0.0_RootHide.deb",
        "NextHomeTorch_1.0.0_Rootless.deb",
        'aria-current="page"',
    ],
    "index.html": ["NEXTHOMETORCH_RECENT_CARD_START", "next-home-torch-ios15-ios16.html"],
    "tutorials.html": ["next-home-torch-ios15-ios16.html"],
    "sitemap.xml": ["next-home-torch-ios15-ios16.html"],
}

for filename, needles in required.items():
    text = Path(filename).read_text()
    for needle in needles:
        assert needle in text, (filename, needle)

article = Path("next-home-torch-ios15-ios16.html").read_text()
assert article.count("pagead2.googlesyndication.com/pagead/js/adsbygoogle.js") == 1
assert "zeshan0727.github.io" not in article
print("Next Home Torch tutorial draft validated")
