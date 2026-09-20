// Pure JS helpers for the cpu-ram plugin: memory formatting, top-app
// aggregation, and safe accessors over the bar's polled snapshot. No Qt
// imports here so the functions stay testable in isolation.

function clamp(n, lo, hi) {
  n = Number(n)
  if (!isFinite(n)) return lo
  return Math.max(lo, Math.min(hi, n))
}

// Compact human memory: "1.2 GB" over a gigabyte, "790 MB" over a
// megabyte, otherwise plain kilobytes.
function fmtMemory(kb) {
  kb = Math.max(0, Number(kb) || 0)
  if (kb >= 1024 * 1024) {
    var g = (kb / 1024 / 1024).toFixed(1)
    return g.replace(/\.0$/, "") + " GB"
  }
  if (kb >= 1024) return Math.round(kb / 1024) + " MB"
  if (kb <= 0) return "0 B"
  return Math.max(1, Math.round(kb)) + " KB"
}

function percentOf(used, total) {
  total = Number(total) || 0
  if (total <= 0) return 0
  return clamp(Math.round(100 * (Number(used) || 0) / total), 0, 100)
}

// Used/total percent for a top-level payload section ("ram", "swap").
function pctFor(stats, key) {
  var o = stats && stats[key]
  if (!o) return 0
  return percentOf(o.used_kb, o.total_kb)
}

function cpuPercent(stats) {
  return clamp(stats && stats.cpu && stats.cpu.percent, 0, 100)
}

// "56°C" from k10temp Tctl; an em dash when the machine reports none.
function cpuTemp(stats) {
  var t = Number(stats && stats.cpu && stats.cpu.temp) || 0
  if (t <= 0) return "\u2014"
  return t.toFixed(1).replace(/\.0$/, "") + "\u00b0C"
}

// Load average as "2.1 · 1.3 · 1.0", or empty when there's no data.
function loadLabel(stats) {
  var load = stats && stats.cpu && stats.cpu.load
  if (!load || !load.length) return ""
  var parts = []
  for (var i = 0; i < load.length; i++) {
    parts.push(Number(load[i]).toFixed(1))
  }
  return parts.join(" \u00b7 ")
}

// Top memory consumers for the panel: [{ name, label }], most-first, where
// label is the app's total RSS formatted for display.
function topApps(stats) {
  var list = stats && stats.topapps ? stats.topapps : []
  var out = []
  for (var j = 0; j < list.length; j++) {
    var rss = Number(list[j].rss_kb) || 0
    out.push({
      name: String(list[j].name || "\u2014"),
      label: fmtMemory(rss)
    })
  }
  return out
}

// Total memory of the top apps shown in the panel, formatted.
function topAppsTotal(stats) {
  var list = stats && stats.topapps ? stats.topapps : []
  if (list.length === 0) return ""
  var total = 0
  for (var i = 0; i < list.length; i++) {
    total += Number(list[i].rss_kb) || 0
  }
  return fmtMemory(total)
}

// One-line card subtitles, skipping fields with no data: "56°C · 2.1 · 1.3 · 1.0".
function cpuSub(stats) {
  var parts = []
  var t = cpuTemp(stats)
  if (t) parts.push(t)
  var load = loadLabel(stats)
  if (load) parts.push(load)
  return parts.join(" \u00b7 ")
}

// "5.5 GB / 15.0 GB": used over total for the RAM card subtitle.
function ramSub(stats) {
  return fmtMemory(value(stats, "ram", "used_kb", 0))
    + " / " + fmtMemory(value(stats, "ram", "total_kb", 0))
}

// "SWAP 0 B / 30.0 GB", or empty when the machine has no swap.
function swapSub(stats) {
  if (value(stats, "swap", "total_kb", 0) <= 0) return ""
  return "SWAP " + fmtMemory(value(stats, "swap", "used_kb", 0))
    + " / " + fmtMemory(value(stats, "swap", "total_kb", 0))
}

// Remainder row so Top5 + Others == system used: { name, label } where name
// is "Others (N processes)". Null when the payload predates the field.
function others(stats) {
  var o = stats && stats.others
  if (!o) return null
  var n = Math.max(0, Math.round(Number(o.count) || 0))
  var noun = n === 1 ? "process" : "processes"
  return {
    name: "Others (" + n + " " + noun + ")",
    label: fmtMemory(Number(o.rss_kb) || 0)
  }
}

// Number field from a payload section, e.g. value(stats, "ram", "used_kb", 0).
function value(stats, key, field, fallback) {
  var o = stats && stats[key]
  return o && o[field] !== undefined ? Number(o[field]) : fallback
}
