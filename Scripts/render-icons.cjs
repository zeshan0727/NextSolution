const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const source = path.join(root, "Design", "AppIcon.svg");
const output = path.join(root, "DailyLedger", "Assets.xcassets", "AppIcon.appiconset");
const sizes = [40, 58, 60, 80, 87, 120, 180, 1024];

fs.mkdirSync(output, { recursive: true });

Promise.all(
  sizes.map((size) =>
    sharp(source)
      .resize(size, size)
      .flatten({ background: "#6D46EE" })
      .removeAlpha()
      .png()
      .toFile(path.join(output, `icon-${size}.png`))
  )
).catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
