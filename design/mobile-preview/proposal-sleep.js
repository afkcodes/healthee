/* Proposal · Sleep. Every section of the current Sleep screen is still here, in the same
   order of thought (last night, this week, the longer view, your own patterns); what
   changes is that each reading says where it sits. Sample values only. */
(() => {
  const { P, esc, hm, clock, chip, verdictOf, rangeBar, hypnogram, band, levels, laneName, stageRows, checks, trendCard, durationCard, timingCard, scale, frame, dayAxis } = H.p;
  const S = {
    score: 66,
    vitals: [
      ['heart', 'heart', 'Resting heart', 53, 'bpm', [50, 62], [52, 57], 'down'],
      ['fitness', 'activity', 'HRV', 61, 'ms', [35, 75], [44, 58], 'up'],
      ['oxygen', 'drop', 'Blood oxygen', 99, '%', [92, 100], [96, 99], 'up'],
      ['oxygen', 'cloud', 'Breathing', 14, '/min', [10, 20], [13, 15], 'steady'],
      ['stress', 'sun', 'Skin temperature', 34.2, '°C', [32, 36], [33.6, 34.5], 'steady'],
    ],
    week: [286, 344, 441, 292, 574, 521, 526], need: 480,
    fortnight: {
      efficiency: { title: 'Sleep efficiency', tone: 'sleep', icon: 'insights', unit: '%', better: 'up', ceiling: 100, values: [71, 75, 98, 98, 95, 98, 93, 99, 97, 97, 96, 91, 98, 99], previous: 90, normal: [90, 99], span: ['28 Sep', '11 Oct'], period: 'over 14 nights', before: 'the 14 before' },
      regularity: { title: 'Sleep regularity', tone: 'sleep', icon: 'insights', unit: 'SRI', better: 'up', values: [54, 52, 51, 55, 62, 64, 68, 73, 75, 76, 75, 72, 72, 72], previous: 58, normal: [58, 74], span: ['28 Sep', '11 Oct'], period: 'over 14 nights', before: 'the 14 before' },
      hrv: { title: 'Heart-rate variability', tone: 'fitness', icon: 'activity', unit: 'ms', better: 'up', values: [56, 46, 50, 41, 50, 42, 46, 45, 53, 52, 51, 47, 40, 61], previous: 47, normal: [44, 58], span: ['28 Sep', '11 Oct'], period: 'over 14 nights', before: 'the 14 before' },
    },
    offPattern: [['25 Sep', '21:23', '4.9 h early'], ['10 Oct', '21:43', '4.5 h early'], ['8 Oct', '21:55', '4.3 h early'], ['9 Oct', '22:25', '3.8 h early']],
    naps: [['11 Oct', '16:02', '16:49', [['light', 14], ['deep', 9], ['light', 7], ['deep', 3], ['rem', 2], ['deep', 2], ['rem', 4], ['light', 6]]], ['11 Oct', '08:15', '09:03', [['light', 15], ['awake', 1], ['light', 9], ['awake', 1], ['light', 8], ['rem', 9], ['light', 5]]], ['7 Oct', '15:45', '17:15', [['light', 22], ['deep', 26], ['light', 12], ['rem', 17], ['light', 13]]], ['7 Oct', '12:34', '13:12', [['light', 21], ['awake', 2], ['light', 15]]], ['5 Oct', '17:29', '18:25', [['light', 19], ['deep', 14], ['light', 11], ['rem', 8], ['light', 4]]]],
    patterns: [
      ['opposite', 'Recovery', 'Resting heart rate', 3, '60 days'],
      ['together', 'Overnight HRV', 'Recovery', 3, '29 days'],
      ['opposite', 'Sleep regularity', 'Sleep debt', 3, '47 days · strongest a day apart'],
      ['opposite', 'Sleep regularity', 'Resting calories', 3, '47 days · strongest a day apart'],
      ['together', 'Overnight blood oxygen', 'Vigorous minutes', 2, '28 days · strongest a day apart'],
    ],
  };
  const jump = () => `<nav class="p-jump" aria-label="On this page">${[['p-night', 'Last night'], ['p-week', 'This week'], ['p-longer', 'Longer view'], ['p-patterns', 'Your patterns']].map(([target, label], index) => `<button data-action="jump" data-target="${target}" ${index ? '' : 'aria-current="true"'}>${label}</button>`).join('')}</nav>`;
  const head = (id, title, note) => `<div class="p-part" id="${id}"><h2>${title}</h2><p>${note}</p></div>`;
  const vitals = () => `<div class="p-vitals">${S.vitals.map(([tone, icon, name, value, unit, [min, max], usual, better]) => {
    const verdict = verdictOf(value, usual, better === 'steady' ? 'up' : better), steady = better === 'steady' && verdict.kind !== 'steady';
    return `<div class="p-vital" data-tone="${tone}"><span class="p-vital-name">${H.icon(icon)}${name}</span><strong>${value}<small> ${unit}</small></strong>
      ${rangeBar({ value, min, max, band: usual, label: `${name} ${value} ${unit}. Your usual range is ${usual[0]} to ${usual[1]}.`, ends: [min, max, `usual ${usual[0]} to ${usual[1]}`] })}
      <small class="p-vital-line"><span class="p-chip ${steady ? 'watch' : verdict.kind}">${verdict.word}</span>${better === 'up' ? 'Higher is better.' : better === 'down' ? 'Lower is better.' : 'Close to your usual is better.'}</small></div>`;
  }).join('')}</div>`;
  const needWeek = () => {
    const y = scale(0, 600, 16, 112);
    let content = frame(y, [0, 240, 480], value => `${value / 60}h`) + `<path class="p-need" d="M4 ${y(S.need).toFixed(1)}H306"/>`;
    S.week.forEach((minutes, index) => {
      const x = 26 + index * 43 - 12, met = minutes >= S.need;
      if (!met) content += `<rect class="p-owed" x="${x}" y="${y(S.need).toFixed(1)}" width="24" height="${(y(minutes) - y(S.need)).toFixed(1)}" rx="4"/>`;
      content += `<rect class="p-bar ${met ? 'met' : 'current'}" x="${x}" y="${y(minutes).toFixed(1)}" width="24" height="${(y(0) - y(minutes)).toFixed(1)}" rx="4"/><text class="p-value" text-anchor="middle" x="${x + 12}" y="${(y(Math.max(minutes, met ? minutes : S.need)) - 5).toFixed(1)}">${met ? '✓' : `−${Math.floor((S.need - minutes) / 60)}:${String((S.need - minutes) % 60).padStart(2, '0')}`}</text>`;
    });
    return `<svg class="p-chart" viewBox="0 0 340 142" role="img" aria-label="Sleep against an 8 hour need on each of the last seven nights">${content}${dayAxis()}</svg>`;
  };
  const lower = name => name.toLowerCase().replace('hrv', 'HRV');
  const short = minutes => minutes < 60 ? `${minutes}m` : hm(minutes);
  const napLength = nap => nap[3].reduce((sum, item) => sum + item[1], 0);
  const napRow = nap => {
    const drawn = band(nap[3], { left: 0, width: 220, top: 2, row: 9, gap: 2 });
    return `<div class="p-nap"><div><strong>${short(napLength(nap))}</strong><small>${nap[0]}</small></div><div><svg class="p-chart" viewBox="0 0 220 ${drawn.bottom + 2}" role="img" aria-label="Nap on ${nap[0]} from ${nap[1]} to ${nap[2]}, by stage">${drawn.content}</svg><p><span>${nap[1]}</span><span>${nap[2]}</span></p></div></div>`;
  };
  /* The same band with the two signals that ran alongside it, and one cursor through all three. */
  const series = (night, base, swing, lift) => {
    const points = []; let at = 0;
    night.timeline.forEach(([stage, minutes]) => { for (let minute = 0; minute < minutes; minute += 3) { const t = at + minute; points.push([t, base + lift[stage] + Math.sin(t / 17) * swing + Math.sin(t / 5.3) * swing * .45]); } at += minutes; });
    return points.map(([t], index) => { const near = points.slice(Math.max(0, index - 3), index + 4); return [t, near.reduce((sum, point) => sum + point[1], 0) / near.length]; });
  };
  const nightDetail = night => {
    const total = night.wake - night.bed, left = 4, width = 300, x = minute => left + minute / total * width;
    const heart = series(night, 58, 2.2, { awake: 12, rem: 6, light: 1, deep: -4 }), breath = series(night, 14, .35, { awake: 1.2, rem: .5, light: 0, deep: -.6 });
    const trace = (points, top, height, low, high) => points.map(([t, value], index) => `${index ? 'L' : 'M'}${x(t).toFixed(1)},${(top + height - (value - low) / (high - low) * height).toFixed(1)}`).join(' ');
    const drawn = band(night.timeline, { left, width, top: 62, row: 22 });
    const breathTop = drawn.bottom + 12, bottom = breathTop + 26;
    const stops = []; let at = 0;
    night.timeline.forEach(([stage, minutes]) => { stops.push([at, at + minutes, stage]); at += minutes; });
    const data = esc(JSON.stringify({ bed: night.bed, total, stops, heart: heart.map(([t, v]) => [t, Math.round(v)]), breath: breath.map(([t, v]) => [t, Math.round(v)]) }));
    return `<div class="p-detail" data-night="${data}"><div class="p-detail-read" aria-live="polite"><div><span class="p-eyebrow" data-read="stage">Light</span><strong data-read="span">01:51 to 02:05</strong></div><div data-tone="heart"><span class="p-eyebrow">Heart rate</span><strong><b data-read="heart">59</b><small> bpm</small></strong></div><div data-tone="oxygen"><span class="p-eyebrow">Breathing</span><strong><b data-read="breath">14</b><small> /min</small></strong></div></div>
      <svg class="p-chart" viewBox="0 0 340 ${bottom + 20}" role="img" aria-label="Sleep stages with heart rate above and breathing below, from ${clock(night.bed)} to ${clock(night.wake)}">
        <text class="p-axis" text-anchor="end" x="338" y="14">75</text><text class="p-axis" text-anchor="end" x="338" y="54">50</text><path class="p-grid" d="M${left} 10H306M${left} 50H306"/>
        <path class="p-trace heart" d="${trace(heart, 10, 40, 50, 75)}"/>${drawn.content}
        ${levels.map(stage => `<text class="p-axis" text-anchor="end" x="338" y="${(drawn.yTop(stage) + drawn.height(stage) / 2 + 3.5).toFixed(1)}">${laneName[stage]}</text>`).join('')}
        <path class="p-trace breath" d="${trace(breath, breathTop, 26, 12, 16.5)}"/><text class="p-axis" text-anchor="end" x="338" y="${breathTop + 16}">/min</text>
        <path class="p-cursor" data-read="cursor" d="M${left} 4V${bottom}"/>
        <text class="p-axis" x="${left}" y="${bottom + 16}">${clock(night.bed)}</text><text class="p-axis" text-anchor="end" x="306" y="${bottom + 16}">${clock(night.wake)}</text></svg>
      <input class="p-scrub" type="range" min="0" max="${total}" value="0" aria-label="Move through the night"><p class="p-legend">Drag to move through the night. Heart rate is the top line, breathing the bottom one.</p></div>`;
  };
  document.addEventListener('input', event => {
    const scrub = event.target.closest?.('.p-scrub'); if (!scrub) return;
    const root = scrub.closest('.p-detail'), night = JSON.parse(root.dataset.night), minute = Number(scrub.value);
    const stop = night.stops.find(([from, to]) => minute >= from && minute < to) || night.stops.at(-1), near = list => list.reduce((best, point) => Math.abs(point[0] - minute) < Math.abs(best[0] - minute) ? point : best)[1];
    const set = (name, value) => { root.querySelector(`[data-read="${name}"]`).textContent = value; };
    set('stage', `${laneName[stop[2]]} · ${stop[1] - stop[0]} min`); set('span', `${clock(night.bed + stop[0])} to ${clock(night.bed + stop[1])}`); set('heart', near(night.heart)); set('breath', near(night.breath));
    const at = (4 + minute / night.total * 300).toFixed(1), cursor = root.querySelector('[data-read="cursor"]');
    cursor.setAttribute('d', cursor.getAttribute('d').replace(/^M[\d.]+/, `M${at}`));
  });
  const patternRow = ([kind, first, second, strength, span]) => `<div class="p-pattern"><div class="p-pattern-pair"><span>${first}<b>↑</b></span><i></i><span>${second}<b>${kind === 'together' ? '↑' : '↓'}</b></span></div>
    <p>Higher ${lower(first)} usually came with <strong>${kind === 'together' ? 'higher' : 'lower'}</strong> ${lower(second)}.</p>
    <small><span class="p-strength" aria-hidden="true">${[1, 2, 3].map(step => `<i class="${step <= strength ? 'on' : ''}"></i>`).join('')}</span>${strength === 3 ? 'Moved closely' : 'Moved moderately'} · ${span}</small></div>`;
  H.screens['p-sleep'] = () => {
    const night = P.night, total = P.debt.fortnight.reduce((sum, minutes) => sum + minutes, 0), weekShort = S.week.reduce((sum, minutes) => sum + Math.max(0, S.need - minutes), 0), napTotal = S.naps.reduce((sum, nap) => sum + napLength(nap), 0);
    const panel = (icon, title, body, tone = 'sleep') => `<section class="panel p-panel" data-tone="${tone}"><h3 class="panel-title">${H.icon(icon)}${title}</h3>${body}</section>`;
    return `<div class="p-screen" data-tone="sleep">
      <header class="page-header p-header"><div class="grow"><h1>Sleep</h1><p class="date">Night of Tue, 15 Sep</p></div><a href="#settings" class="icon-button avatar" aria-label="Profile and settings">A</a></header>
      ${jump()}
      <section class="p-sleep-hero" id="p-night"><div class="p-hero-row"><div><p class="p-eyebrow">Time asleep</p><div class="p-big">6<small>h</small> 24<small>m</small></div></div><div class="p-device"><strong>${S.score}</strong><span>Amazfit score</span><small>Device estimate</small></div></div>
        ${rangeBar({ value: 384, min: 240, max: 540, band: [350, 430], label: 'Asleep 6 hours 24 minutes. Your usual range is 5 hours 50 to 7 hours 10.', ends: ['4h', '9h', 'usual 5h 50m to 7h 10m'] })}
        <p class="p-key-line">${chip(verdictOf(384, [350, 430]))} <strong>1h 36m short</strong> of your 8h need.</p>
        <dl class="p-facts"><div><dt>In bed</dt><dd>${clock(night.bed)}</dd></div><div><dt>Up</dt><dd>${clock(night.wake)}</dd></div><div><dt>Time in bed</dt><dd>${hm(night.wake - night.bed)}</dd></div></dl></section>
      ${panel('moon', 'How your night unfolded', `${hypnogram(night)}${H.stageLegend ? H.stageLegend() : ''}`)}
      ${panel('heart', 'Your night, minute by minute', nightDetail(night), 'heart')}
      ${panel('moon', 'Every stage, accounted for', `${stageRows(night.stages)}<p class="p-legend">Proportions use the supplied stage total. Stage totals and time-asleep estimates can differ.</p>`)}
      ${panel('check', 'Your four sleep checks', `<p class="p-legend first">The shaded part of each bar is the reference range. The mark is last night.</p>${checks()}<p class="p-legend">Four independent checks, not a combined score. The 7 to 9h check differs from the 8h sleep-need reference.</p>`)}
      ${panel('heart', 'Your body overnight', `<p class="p-legend first">The shaded part of each bar is your own last 14 nights. The mark is last night.</p>${vitals()}`, 'heart')}
      ${head('p-week', 'This week', '5 to 11 Oct · seven measured nights')}
      ${panel('clock', 'Sleep need & debt', `<div class="p-two"><div><p class="p-eyebrow">This week</p><div class="p-mid">${hm(weekShort)}</div><small>short of your 8h need, in total</small></div><div><p class="p-eyebrow">Last 14 nights</p><div class="p-mid">${(total / 60).toFixed(1)}<small> h</small></div><small>the modelled debt · about ${hm(total / 14)} a night</small></div></div>${needWeek()}<p class="p-legend">The faint part of a bar is what that night still needed. A tick means the night met 8h. The week's figure and the 14-night model are two different sums.</p>`)}
      ${durationCard(P.week)}${timingCard(P.week)}
      ${panel('clock', 'Nights off your pattern', `<div class="p-two"><div><p class="p-eyebrow">Typical bedtime band</p><div class="p-mid">5.4<small> h wide</small></div><small>loose (3h or more) · your biggest lever</small></div><div><p class="p-eyebrow">Usual times</p><div class="p-mid">02:15</div><small>bed · wake about 07:58</small></div></div><table class="p-table"><thead><tr><th>Night</th><th>In bed</th><th>Against your usual</th></tr></thead><tbody>${S.offPattern.map(([day, bed, gap]) => `<tr><td>${day}</td><td>${bed}</td><td>${gap}</td></tr>`).join('')}</tbody></table><p class="p-legend">Nights more than two hours from your usual bedtime.</p>`)}
      ${head('p-longer', 'Beyond a single night', '28 Sep to 11 Oct · 14 nights')}
      ${trendCard(S.fortnight.efficiency)}${trendCard(S.fortnight.regularity)}${trendCard(S.fortnight.hrv)}
      ${panel('moon', 'Naps & your day', `<div class="p-two"><div><p class="p-eyebrow">Last 7 days</p><div class="p-mid">${hm(napTotal)}</div><small>in ${S.naps.length} naps</small></div><div><p class="p-eyebrow">Longest</p><div class="p-mid">${hm(Math.max(...S.naps.map(napLength)))}</div><small>on 7 Oct</small></div></div>${S.naps.map(napRow).join('')}`)}
      ${head('p-patterns', 'In your own data', 'What moved together in your history. Never what caused what.')}
      <section class="panel p-panel" data-tone="oxygen">${S.patterns.map(patternRow).join('')}<p class="p-legend">Single-subject and observational: patterns found in your history, not effects shown in a trial.</p></section>
      <p class="p-more">${H.link('Sleep recommendations', 'actions')}</p>
      ${H.footer()}</div>`;
  };
})();
