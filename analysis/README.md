# Analysis engine

build_equity_reports.py reads the source exports, normalizes realized PnL events, writes platform-separated metrics and charts, and produces a transparent screening shortlist.

The engine intentionally does not re-optimize strategy parameters, change strategy stops/targets/entries/exits/quantities, add assumed costs on top of source costs, convert timestamps between platform timezones, or apply Tradeify/other prop-firm rules.
