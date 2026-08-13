#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "NextReminder" / "Sources"

performance = SOURCES / "PerformanceAndRepeat.swift"
text = performance.read_text()
old = '''            HStack(spacing: 8) {
                ForEach(Array(zip(ReminderWeekday.all.prefix(5), metrics.dailyCounts)), id: \.0.id) { day, count in
                    VStack(spacing: 6) {
                        Text("\\(count)")
                            .font(.subheadline.bold())
                        Text(day.shortTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.nextSecondaryFill, in: RoundedRectangle(cornerRadius: 10))
                }
            }
'''
new = '''            HStack(spacing: 8) {
                ForEach(Array(metrics.dailyCounts.enumerated()), id: \.offset) { item in
                    let day = ReminderWeekday.all[item.offset]
                    VStack(spacing: 6) {
                        Text("\\(item.element)")
                            .font(.subheadline.bold())
                        Text(day.shortTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.nextSecondaryFill, in: RoundedRectangle(cornerRadius: 10))
                }
            }
'''
if old not in text:
    raise SystemExit("Performance day-row source was not found")
performance.write_text(text.replace(old, new, 1))

print("v1.2.1 compatibility fixes applied.")
