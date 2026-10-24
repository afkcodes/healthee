/* Proposal · "read it in one look". Three screens beside the current design, on the same
   tokens and tones, so the two can be compared route for route: #p-today, #p-sleep,
   #p-trends. Sample values only; nothing here is a real measurement. */
(() => {
  const esc = H.escape;
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const hm = minutes => `${Math.floor(minutes / 60)}h ${String(Math.round(minutes % 60)).padStart(2, '0')}m`;
  const clock = minutes => { const m = ((Math.round(minutes) % 1440) + 1440) % 1440; return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`; };

  /* ── sample data ─────────────────────────────────────────────────────────── */
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const P = {
    recovery: { value: 51, usual: [55, 72], remaining: 43 },
    sleep: { minutes: 384, need: 480, usual: [350, 430] },
    steps: { value: 3159, target: 10000, usual: [4200, 8900] },
    night: {
      bed: 111, wake: 504, // minutes after midnight: 01:51 → 08:24
      timeline: [['light', 14], ['deep', 31], ['light', 22], ['rem', 9], ['awake', 3], ['light', 41], ['deep', 19], ['light', 18], ['rem', 27], ['light', 62], ['deep', 16], ['light', 21], ['rem', 24], ['awake', 4], ['light', 33], ['rem', 29], ['awake', 3], ['light', 17]],
      stages: [['deep', 'Deep', 66, 72], ['rem', 'REM', 89, 81], ['light', 'Light', 229, 221], ['awake', 'Awake', 10, 14]],
    },
    debt: { lastNight: 96, fortnight: [72, 131, 45, 158, 96, 118, 204, 64, 151, 99, 176, 143, 181, 96] },
    trends: {
      hrv: { title: 'Overnight HRV', tone: 'fitness', icon: 'activity', unit: 'ms', better: 'up', values: [58, 63, 49, 61, 66, null, 64], previous: 57, normal: [52, 66] },
      rhr: { title: 'Resting heart rate', tone: 'heart', icon: 'heart', unit: 'bpm', better: 'down', values: [62, 60, 66, 61, 59, null, 60], previous: 63, normal: [58, 63] },
      deep: { title: 'Deep sleep', tone: 'sleep', icon: 'moon', unit: 'min', better: 'up', values: [64, 54, 76, 62, 93, null, 102], previous: 64, normal: [58, 84], time: true },
    },
    week: [ // bed and wake as minutes after 18:00 the evening before, plus stage minutes
      { bed: 590, wake: 878, deep: 64, light: 172, rem: 50 }, { bed: 503, wake: 855, deep: 54, light: 206, rem: 84 },
      { bed: 407, wake: 857, deep: 76, light: 283, rem: 82 }, { bed: 537, wake: 839, deep: 62, light: 175, rem: 55 },
      { bed: 235, wake: 866, deep: 93, light: 335, rem: 146 }, null, { bed: 223, wake: 750, deep: 102, light: 294, rem: 125 },
    ],
  };

  /* ── small vocabulary ────────────────────────────────────────────────────── */
  const verdictOf = (value, [low, high], better = 'up') => {
    if (value >= low && value <= high) return { word: 'In your usual range', kind: 'steady' };
    const above = value > high;
    const good = (above && better === 'up') || (!above && better === 'down');
    return { word: `${above ? 'Above' : 'Below'} your usual`, kind: good ? 'good' : 'watch' };
  };
  const chip = verdict => `<span class="p-chip ${verdict.kind}">${verdict.word}</span>`;
  /* A track, the person's usual range drawn on it, and where today sits. */
  const rangeBar = ({ value, min, max, band, label, ends }) => {
    const pct = v => clamp((v - min) / (max - min) * 100, 0, 100);
    return `<div class="p-range" role="img" aria-label="${esc(label)}"><div class="p-range-track"><i class="p-range-band" style="left:${pct(band[0])}%;width:${pct(band[1]) - pct(band[0])}%"></i><b class="p-range-mark" style="left:${pct(value)}%"></b></div><div class="p-range-ends"><span>${ends[0]}</span><span class="p-range-usual" style="left:${(pct(band[0]) + pct(band[1])) / 2}%">${ends[2]}</span><span>${ends[1]}</span></div></div>`;
  };

  /* ── Today ───────────────────────────────────────────────────────────────── */
  const keyMetric = ({ tone, icon, name, route, value, unit, verdict, bar, line }) => `<a class="p-key" data-tone="${tone}" href="#${route}">
    <div class="p-key-top"><span class="p-key-name">${H.icon(icon)}${name}</span>${chip(verdict)}${H.icon('chevron', 'small')}</div>
    <div class="p-key-value">${value}<small>${unit}</small></div>${rangeBar(bar)}<p class="p-key-line">${line}</p></a>`;
  const todayKeys = () => {
    const r = P.recovery, s = P.sleep, m = P.steps;
    return `<section class="p-keys" aria-label="Today's three">
      ${keyMetric({ tone: 'recovery', icon: 'heart', name: 'Recovery', route: 'recovery', value: r.value, unit: ' / 100', verdict: verdictOf(r.value, r.usual), bar: { value: r.value, min: 0, max: 100, band: r.usual, label: `Recovery ${r.value}. Your usual range is ${r.usual[0]} to ${r.usual[1]}.`, ends: ['0', '100', `usual ${r.usual[0]} to ${r.usual[1]}`] }, line: `<strong>${r.remaining} left for today.</strong> You started lower than most of your mornings.` })}
      ${keyMetric({ tone: 'sleep', icon: 'moon', name: 'Sleep', route: 'p-sleep', value: hm(s.minutes), unit: '', verdict: verdictOf(s.minutes, s.usual), bar: { value: s.minutes, min: 240, max: 540, band: s.usual, label: `Asleep ${hm(s.minutes)}. Your usual range is ${hm(s.usual[0])} to ${hm(s.usual[1])}.`, ends: ['4h', '9h', `usual ${hm(s.usual[0])} to ${hm(s.usual[1])}`] }, line: `<strong>${hm(s.need - s.minutes)} short</strong> of your ${hm(s.need)} need.` })}
      ${keyMetric({ tone: 'movement', icon: 'walk', name: 'Movement', route: 'activity', value: m.value.toLocaleString(), unit: ' steps', verdict: verdictOf(m.value, m.usual), bar: { value: m.value, min: 0, max: 12000, band: m.usual, label: `${m.value} steps. Your usual range by the end of a day is ${m.usual[0]} to ${m.usual[1]}.`, ends: ['0', '12k', `usual ${(m.usual[0] / 1000).toFixed(1)}k to ${(m.usual[1] / 1000).toFixed(1)}k`] }, line: `<strong>${(m.target - m.value).toLocaleString()} to go</strong> to your ${m.target.toLocaleString()} target. The day is not over.` })}
    </section>`;
  };
  H.screens['p-today'] = () => `<div class="p-screen">
    <header class="page-header p-header"><div class="grow"><h1>Today</h1><p class="date">Tue, 16 Sep · latest sample</p></div><a class="icon-button p-coach" href="#coach" aria-label="Ask your coach">${H.icon('coach')}</a><a href="#settings" class="icon-button avatar" aria-label="Profile and settings">A</a></header>
    <div class="p-hero">${H.bioHero()}</div>
    <div class="p-section-head"><h2>Today's three</h2><a class="text-button" href="#p-trends">Trends${H.icon('arrow', 'small')}</a></div>
    ${todayKeys()}
    <p class="p-legend">The shaded part of each bar is where <strong>your own last 14 days</strong> fell. The mark is today.</p>
    ${H.footer()}</div>`;

  /* ── Sleep: one night ───────────────────────────────────────────────────── */
  const laneName = { awake: 'Awake', rem: 'REM', light: 'Light', deep: 'Deep' };
  /* One continuous band, the way a night actually runs: every minute belongs to a block,
     each stage has its own level, and a thin dotted join carries the eye from one block
     to the next. Awake is a short cap above the band. */
  const levels = ['awake', 'rem', 'light', 'deep'];
  const band = (timeline, { left, width, top, row, awake = row * .55, gap = 3 }) => {
    const total = timeline.reduce((sum, item) => sum + item[1], 0), x = minute => left + minute / total * width;
    const yTop = stage => stage === 'awake' ? top : top + awake + gap + (levels.indexOf(stage) - 1) * (row + gap), height = stage => stage === 'awake' ? awake : row;
    let blocks = '', joins = '', at = 0, before = null;
    timeline.forEach(([stage, minutes]) => {
      const from = x(at), to = x(at + minutes), wide = Math.max(1.6, to - from);
      if (before && before !== stage) {
        const upper = levels.indexOf(before) < levels.indexOf(stage) ? before : stage, lower = upper === before ? stage : before;
        joins += `<path class="p-join" d="M${from.toFixed(1)} ${(yTop(upper) + height(upper)).toFixed(1)}V${yTop(lower).toFixed(1)}"/>`;
      }
      blocks += `<rect class="stage-${stage}" x="${from.toFixed(1)}" y="${yTop(stage).toFixed(1)}" width="${wide.toFixed(1)}" height="${height(stage).toFixed(1)}" rx="${Math.min(3, wide / 2).toFixed(1)}"><title>${laneName[stage]}, ${minutes} min</title></rect>`;
      at += minutes; before = stage;
    });
    return { content: joins + blocks, bottom: top + awake + gap + 3 * row + 2 * gap, yTop, height, total, x };
  };
  const hypnogram = night => {
    const drawn = band(night.timeline, { left: 34, width: 302, top: 4, row: 20 });
    const labels = levels.map(stage => `<text class="p-axis" x="0" y="${(drawn.yTop(stage) + drawn.height(stage) / 2 + 3.5).toFixed(1)}">${laneName[stage]}</text>`).join('');
    return `<svg class="p-chart" viewBox="0 0 340 ${drawn.bottom + 22}" role="img" aria-label="Sleep stages from ${clock(night.bed)} to ${clock(night.wake)}">${labels}${drawn.content}<text class="p-axis" x="34" y="${drawn.bottom + 17}">${clock(night.bed)}</text><text class="p-axis" text-anchor="end" x="336" y="${drawn.bottom + 17}">${clock(night.wake)}</text></svg>`;
  };
  const stageRows = stages => {
    const total = stages.reduce((sum, stage) => sum + stage[2], 0), longest = Math.max(...stages.flatMap(stage => [stage[2], stage[3]]));
    return `<div class="p-split" aria-hidden="true">${stages.map(([key, , minutes]) => `<i class="stage-${key}" style="flex:${minutes}"></i>`).join('')}</div>
      <div class="p-stage-rows">${stages.map(([key, name, minutes, average]) => {
        const gap = minutes - average, same = Math.abs(gap) < 5;
        return `<div class="p-stage-row"><span class="p-stage-name"><i class="stage-${key}"></i>${name}</span><strong>${hm(minutes)}</strong><span class="p-stage-share">${Math.round(minutes / total * 100)}%</span>
          <div class="p-stage-bar"><i class="stage-${key}" style="width:${minutes / longest * 100}%"></i><b style="left:${average / longest * 100}%" title="Your 14-night average"></b></div>
          <small>${same ? 'About your average' : `${Math.abs(gap)} min ${gap > 0 ? 'more' : 'less'} than your average`} (${hm(average)})</small></div>`;
      }).join('')}</div><p class="p-legend">The small mark on each bar is your 14-night average.</p>`;
  };
  const check = ({ name, reading, reference, bar, verdict, line }) => `<div class="p-check"><div class="p-check-top"><span><strong>${name}</strong><small>${reference}</small></span><span class="p-check-reading">${reading}</span></div>${rangeBar(bar)}<p class="p-check-line"><span class="p-chip ${verdict.kind}">${verdict.word}</span>${line}</p></div>`;
  const checks = () => `${check({ name: 'Duration', reading: '6h 24m', reference: 'Reference 7 to 9 hours', bar: { value: 6.4, min: 4, max: 10, band: [7, 9], label: 'Duration 6 hours 24 minutes against a 7 to 9 hour reference', ends: ['4h', '10h', '7 to 9h'] }, verdict: { word: 'Under', kind: 'watch' }, line: '36 minutes under the reference.' })}
    ${check({ name: 'Efficiency', reading: '97.5%', reference: 'Reference 85% or more', bar: { value: 97.5, min: 70, max: 100, band: [85, 100], label: 'Efficiency 97.5 percent against a reference of 85 or more', ends: ['70%', '100%', '85% or more'] }, verdict: { word: 'Within', kind: 'steady' }, line: 'Almost all of your time in bed was sleep.' })}
    ${check({ name: 'Regularity', reading: '76', reference: 'Reference 70 or more, out of 100', bar: { value: 76, min: 40, max: 100, band: [70, 100], label: 'Regularity 76 against a reference of 70 or more', ends: ['40', '100', '70 or more'] }, verdict: { word: 'Within', kind: 'steady' }, line: 'Your bed and wake times repeat well.' })}
    ${check({ name: 'Timing', reading: '05:07', reference: 'Middle of your sleep · reference 02:00 to 04:00', bar: { value: 307, min: 0, max: 480, band: [120, 240], label: 'Sleep midpoint 05:07 against a 02:00 to 04:00 reference', ends: ['00:00', '08:00', '02:00 to 04:00'] }, verdict: { word: 'Late', kind: 'watch' }, line: '1h 07m later than the reference window.' })}`;
  const debtBars = nights => {
    const max = 240, left = 4, step = 300 / nights.length;
    let content = [0, 120, 240].map(value => `<path class="p-grid" d="M${left} ${104 - value / max * 92}H306"/><text class="p-axis" text-anchor="end" x="338" y="${108 - value / max * 92}">${value / 60}h</text>`).join('');
    nights.forEach((minutes, index) => { content += `<rect class="p-bar ${index === nights.length - 1 ? 'current' : ''}" x="${(left + index * step + step * .18).toFixed(1)}" y="${(104 - minutes / max * 92).toFixed(1)}" width="${(step * .64).toFixed(1)}" height="${(minutes / max * 92).toFixed(1)}" rx="3"><title>${hm(minutes)} short</title></rect>`; });
    return `<svg class="p-chart" viewBox="0 0 340 122" role="img" aria-label="Sleep shortfall on each of the last 14 nights">${content}<text class="p-axis" x="${left}" y="120">14 nights ago</text><text class="p-axis" text-anchor="end" x="306" y="120">last night</text></svg>`;
  };
  /* ── Trends: one card grammar for every metric ──────────────────────────── */
  const average = values => { const present = values.filter(value => value !== null); return present.reduce((sum, value) => sum + value, 0) / present.length; };
  const scale = (low, high, top = 14, bottom = 118) => value => bottom - (value - low) / (high - low) * (bottom - top);
  const frame = (y, ticks, format) => ticks.map(value => `<path class="p-grid" d="M4 ${y(value).toFixed(1)}H306"/><text class="p-axis" text-anchor="end" x="338" y="${(y(value) + 4).toFixed(1)}">${format(value)}</text>`).join('');
  const dayAxis = () => days.map((day, index) => `<text class="p-axis" text-anchor="middle" x="${26 + index * 43}" y="138">${day}</text>`).join('');
  const dots = metric => {
    const present = metric.values.filter(value => value !== null), low = Math.min(...present, metric.normal[0]) - 6, high = Math.min(metric.ceiling ?? Infinity, Math.max(...present, metric.normal[1]) + 6), y = scale(low, high, 24), mean = average(metric.values);
    const format = value => metric.time ? `${Math.floor(value / 60)}:${String(Math.round(value % 60)).padStart(2, '0')}` : Math.round(value);
    let content = frame(y, [low + 2, (low + high) / 2, metric.ceiling === high ? high : high - 2], format) + `<rect class="p-normal" x="4" y="${y(metric.normal[1]).toFixed(1)}" width="302" height="${(y(metric.normal[0]) - y(metric.normal[1])).toFixed(1)}" rx="4"/><path class="p-mean" d="M4 ${y(mean).toFixed(1)}H306"/>`;
    let run = [];
    const flush = () => { if (run.length > 1) content += `<path class="p-line" d="${run.map((point, index) => `${index ? 'L' : 'M'}${point[0]},${point[1].toFixed(1)}`).join(' ')}"/>`; run = []; };
    const count = metric.values.length, many = count > 8, at = index => many ? 12 + index * (286 / (count - 1)) : 26 + index * 43;
    const lowest = Math.min(...present), highest = Math.max(...present);
    metric.values.forEach((value, index) => { if (value === null) flush(); else run.push([at(index).toFixed(1), y(value)]); });
    flush();
    metric.values.forEach((value, index) => {
      const x = at(index).toFixed(1), last = index === count - 1;
      if (value === null) { if (!many) content += `<text class="p-missing" text-anchor="middle" x="${x}" y="114">no data</text>`; return; }
      const outside = value < metric.normal[0] || value > metric.normal[1];
      const named = !many || last || (value === lowest && metric.values.indexOf(lowest) === index) || (value === highest && metric.values.indexOf(highest) === index);
      content += `<circle class="p-dot ${outside ? 'outside' : ''} ${index === metric.values.length - 1 ? 'current' : ''}" cx="${x}" cy="${y(value).toFixed(1)}" r="${many ? 3.5 : 4.5}"/>${named ? `<text class="p-value" text-anchor="${many && last ? 'end' : 'middle'}" x="${many && last ? 306 : x}" y="${(y(value) - 9).toFixed(1)}">${format(value)}</text>` : ''}`;
    });
    return `<svg class="p-chart" viewBox="0 0 340 142" role="img" aria-label="${esc(metric.title)} across ${count} nights">${content}${many ? `<text class="p-axis" x="4" y="138">${metric.span[0]}</text><text class="p-axis" text-anchor="end" x="306" y="138">${metric.span[1]}</text>` : dayAxis()}</svg>`;
  };
  const trendCard = metric => {
    const mean = average(metric.values), change = mean - metric.previous, inside = metric.values.filter(value => value !== null && value >= metric.normal[0] && value <= metric.normal[1]).length, measured = metric.values.filter(value => value !== null).length;
    const show = value => metric.time ? hm(value) : `${Math.round(value)}<small> ${metric.unit}</small>`;
    const better = (change > 0 && metric.better === 'up') || (change < 0 && metric.better === 'down'), flat = Math.abs(change) < 1;
    const plain = value => metric.time ? hm(value) : `${Math.round(value)} ${metric.unit}`;
    return `<section class="panel p-panel p-trend" data-tone="${metric.tone}"><div class="p-trend-head"><h3 class="panel-title">${H.icon(metric.icon)}${metric.title}</h3><span class="p-direction">${metric.better === 'up' ? 'Higher is better' : 'Lower is better'}</span></div>
      <div class="p-trend-read"><div class="p-mid">${show(mean)}</div><span class="p-eyebrow">average ${metric.period || 'this week'}</span><span class="p-delta ${flat ? 'steady' : better ? 'good' : 'watch'}">${flat ? 'No change' : `${change > 0 ? '↑' : '↓'} ${metric.time ? `${Math.round(Math.abs(change))} min` : Math.round(Math.abs(change))}`} vs ${metric.before || 'last week'}</span></div>
      ${dots(metric)}
      <p class="p-sentence"><strong>${inside} of ${measured} nights</strong> were inside your normal range of ${plain(metric.normal[0])} to ${plain(metric.normal[1])}.</p></section>`;
  };
  const durationCard = week => {
    const y = scale(0, 660), nights = week.map(night => night ? night.deep + night.light + night.rem : null), mean = average(nights);
    let content = frame(y, [0, 240, 480], value => `${value / 60}h`) + `<path class="p-need" d="M4 ${y(480).toFixed(1)}H306"/><path class="p-mean" d="M4 ${y(mean).toFixed(1)}H306"/>`;
    week.forEach((night, index) => {
      const x = 26 + index * 43 - 11;
      if (!night) { content += `<text class="p-missing" text-anchor="middle" x="${x + 11}" y="114">no data</text>`; return; }
      let from = 0;
      ['deep', 'light', 'rem'].forEach(stage => { content += `<rect class="stage-${stage}" x="${x}" y="${y(from + night[stage]).toFixed(1)}" width="22" height="${(y(from) - y(from + night[stage])).toFixed(1)}"/>`; from += night[stage]; });
      content += `<text class="p-value" text-anchor="middle" x="${x + 11}" y="${(y(from) - 6).toFixed(1)}">${Math.floor(from / 60)}:${String(from % 60).padStart(2, '0')}</text>`;
    });
    const met = nights.filter(minutes => minutes !== null && minutes >= 420).length;
    return `<section class="panel p-panel p-trend" data-tone="sleep"><div class="p-trend-head"><h3 class="panel-title">${H.icon('moon')}Time asleep</h3><span class="p-direction">7 to 9 hours is the reference</span></div>
      <div class="p-trend-read"><div class="p-mid">${hm(mean)}</div><span class="p-eyebrow">average this week</span><span class="p-delta good">↑ 1h 19m vs last week</span></div>
      <svg class="p-chart" viewBox="0 0 340 142" role="img" aria-label="Time asleep on each of the last seven nights, by stage">${content}${dayAxis()}</svg>${H.stageLegend ? H.stageLegend() : ''}
      <p class="p-sentence"><strong>${met} of ${nights.filter(minutes => minutes !== null).length} nights</strong> reached 7 hours. The upper dashed line is your 8h need, the lower one your average.</p></section>`;
  };
  const timingCard = week => {
    const y = value => 14 + (value - 180) / (960 - 180) * 104; // 21:00 at the top, 10:00 at the bottom
    let content = [180, 540, 900].map(value => `<path class="p-grid" d="M4 ${y(value).toFixed(1)}H306"/><text class="p-axis" text-anchor="end" x="338" y="${(y(value) + 4).toFixed(1)}">${clock(value + 1080)}</text>`).join('');
    week.forEach((night, index) => {
      const x = 26 + index * 43 - 7;
      if (!night) { content += `<text class="p-missing" text-anchor="middle" x="${x + 7}" y="114">no data</text>`; return; }
      content += `<rect class="p-bar current" x="${x}" y="${y(night.bed).toFixed(1)}" width="14" height="${(y(night.wake) - y(night.bed)).toFixed(1)}" rx="7"/><text class="p-value" text-anchor="middle" x="${x + 7}" y="${(y(night.bed) - 5).toFixed(1)}">${clock(night.bed + 1080)}</text><text class="p-value" text-anchor="middle" x="${x + 7}" y="${(y(night.wake) + 12).toFixed(1)}">${clock(night.wake + 1080)}</text>`;
    });
    const beds = week.filter(Boolean).map(night => night.bed), spread = Math.max(...beds) - Math.min(...beds);
    return `<section class="panel p-panel p-trend" data-tone="sleep"><div class="p-trend-head"><h3 class="panel-title">${H.icon('clock')}Bed and wake times</h3><span class="p-direction">Steadier is better</span></div>
      <div class="p-trend-read"><div class="p-mid">${hm(spread)}</div><span class="p-eyebrow">between your earliest and latest bedtime</span></div>
      <svg class="p-chart" viewBox="0 0 340 142" role="img" aria-label="Bedtime and wake time on each of the last seven nights">${content}${dayAxis()}</svg>
      <p class="p-sentence">Each bar runs from when you fell asleep to when you woke. <strong>Bars that line up</strong> mean a regular week.</p></section>`;
  };
  H.screens['p-trends'] = () => `<div class="p-screen">
    <header class="page-header detail p-header"><button class="icon-button" data-action="back" aria-label="Go back">${H.icon('back')}</button><div class="grow"><p class="date">7 to 13 Sep</p><h1>Your week</h1></div></header>
    <div class="segment p-ranges" role="group" aria-label="Period"><button aria-pressed="true">Week</button><button aria-pressed="false">Month</button><button aria-pressed="false">6 months</button></div>
    <p class="p-legend first">On every chart: the <strong>shaded band is your normal range</strong> from the last 30 days, the dashed line is this week's average, and a hollow dot is a night outside your range.</p>
    ${trendCard(P.trends.hrv)}${trendCard(P.trends.rhr)}${durationCard(P.week)}${timingCard(P.week)}${trendCard(P.trends.deep)}
    ${H.footer()}</div>`;

  H.p = { P, esc, hm, clock, chip, verdictOf, rangeBar, hypnogram, band, levels, laneName, stageRows, checks, trendCard, durationCard, timingCard, scale, frame, dayAxis, average, days };
  H.directory?.push(['p-today', 'Proposal · Today', 'spark'], ['p-sleep', 'Proposal · Sleep', 'spark'], ['p-trends', 'Proposal · Trends', 'spark']);
})();
