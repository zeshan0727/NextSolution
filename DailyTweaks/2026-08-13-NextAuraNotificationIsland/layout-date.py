from pathlib import Path
p=Path(__file__).with_name('NotificationIsland.xm')
s=p.read_text()
s=s.replace('formatter.dateFormat = @"h:mm a";', 'formatter.dateFormat = @"MMM d · h:mm a";', 1)
s=s.replace('CGFloat timeWidth = 58;', 'CGFloat timeWidth = NANExpanded ? 112.0 : 88.0;', 1)
p.write_text(s)
