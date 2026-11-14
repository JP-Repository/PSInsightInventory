'use strict';

(() => {
  const payload = JSON.parse(document.getElementById('snapshot').textContent);
  const {meta, sections, data, coverage = {}} = payload;
  const collection = data.collection || [];
  const $ = selector => document.querySelector(selector);
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char =>
    ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'})[char]);
  const number = value => Number.isFinite(value) ? value.toLocaleString() : 'Unknown';
  const text = value => value == null ? 'Unknown' : value === true ? 'Yes' : value === false ? 'No' : String(value);
  const rows = key => data[key] || [];
  const status = row => row.Status || row.Outcome || 'Unknown';
  const sample = meta.dataSource === 'Sample';
  const paths = {
    grid:'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
    list:'M8 5h12M8 12h12M8 19h12M3 5h1M3 12h1M3 19h1',
    shield:'M12 3l8 3v6c0 5-8 9-8 9s-8-4-8-9V6zM8 12l3 3 5-6',
    server:'M4 3h16v7H4zM4 14h16v7H4zM7 6h.01M7 17h.01M11 6h6M11 17h6',
    globe:'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M3 12h18M12 3c-5 5-5 13 0 18M12 3c5 5 5 13 0 18',
    folder:'M3 6h7l2 3h9v12H3zM3 6V3h7l2 3',
    link:'M8 16l8-8M9 6l2-2a5 5 0 0 1 7 7l-2 2M15 18l-2 2a5 5 0 0 1-7-7l2-2',
    users:'M8 4a3 3 0 1 1 0 6a3 3 0 0 1 0-6M2 21v-4c0-5 12-5 12 0v4M16 4a3 3 0 0 1 0 6M18 14c3 0 4 2 4 4v3',
    person:'M12 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8M4 21v-2a8 5 0 0 1 16 0v2',
    forest:'M3 17l4-6h-2l4-6 4 6h-2l4 6H3zM9 17v4m6-7 3-6 4 8h-5m1 0v5',
    hierarchy:'M9 3h6v5H9zM3 16h6v5H3zM15 16h6v5h-6zM12 8v4M6 16v-4h12v4',
    layers:'M3 8l9-5 9 5-9 5-9-5zM3 12l9 5 9-5M3 16l9 5 9-5',
    crown:'M3 6l4 4 5-6 5 6 4-4-2 12H5L3 6zM6 21h12',
    text:'M4 5h16M12 5v14m-4 0h8M4 5v3m16-3v3',
    partitions:'M3 4h18v16H3zM3 10h18M9 10v10m6-10v10',
    database:'M4 6a8 3 0 1 0 16 0 8 3 0 1 0-16 0zm0 0v12a8 3 0 0 0 16 0V6M4 12a8 3 0 0 0 16 0',
    lock:'M5 10h14v11H5zM8 10V7a4 4 0 1 1 8 0v3m-4 5v2',
    member:'M9 4a3 3 0 1 1 0 6 3 3 0 0 1 0-6M3 20v-2a6 4 0 0 1 9-4m5-1v8m-4-4h8',
    nested:'M3 3h13v13H3zM8 8h13v13H8z',
    parent:'M12 20V4m-5 5 5-5 5 5M5 20h14',
    identity:'M3 5h18v14H3zM8 9a2 2 0 1 0 0 4 2 2 0 1 0 0-4zm-3 8a3 2 0 0 1 6 0m3-7h4m-4 4h4',
    chip:'M6 6h12v12H6zM9 9h6v6H9zM9 3v3m6-3v3M9 18v3m6-3v3M3 9h3m-3 6h3m12-6h3m-3 6h3',
    monitor:'M3 4h18v12H3zm9 12v4m-5 0h10',
    network:'M9 3h6v6H9zM3 16h5v5H3zM16 16h5v5h-5zM12 9v4m-7 3v-3h14v3',
    forward:'M3 12h17m-6-6 6 6-6 6',
    split:'M4 18h4a4 4 0 0 0 4-4v-4a4 4 0 0 1 4-4h4m-3-3 3 3-3 3M12 14a4 4 0 0 0 4 4h4m-3-3 3 3-3 3',
    sync:'M20 10a8 8 0 0 0-14-4L3 9m0-5v5h5m-4 5a8 8 0 0 0 14 4l3-3m0 5v-5h-5',
    certificate:'M5 3h14v13H5zM8 7h8m-8 4h5m2 5 2 5 2-2 2 1-2-5',
    share:'M4 5h7l2 3h7v10H4zM9 13h7m-3-3 3 3-3 3',
    pin:'M20 10c0 6-8 11-8 11S4 16 4 10a8 8 0 0 1 16 0zM12 7a3 3 0 1 0 0 6 3 3 0 1 0 0-6',
    calendar:'M4 6h16v15H4zM4 10h16M8 3v5m8-5v5m-8 7h2m4 0h2',
    sliders:'M4 6h16M4 12h16M4 18h16M8 4v4m8 2v4m-6 2v4',
    document:'M5 3h10l4 4v14H5zM15 3v5h4M8 12h8m-8 4h8',
    filter:'M3 4h18l-7 8v6l-4 2v-8z',
    key:'M8 4a4 4 0 1 0 0 8 4 4 0 1 0 0-8zm3 7 9 9m-5-4 2-2m0 4 2-2',
    count:'M8 3 6 21m12-18-2 18M3 9h18M2 15h18',
    flag:'M5 21V4m0 1h14l-3 4 3 4H5',
    company:'M4 21V7l8-4 8 4v14zM8 9h1m6 0h1m-8 4h1m6 0h1m-5 8v-4h2v4',
    status:'M3 12h4l3-7 4 14 3-7h4',
    history:'M4 11a8 8 0 1 1 2 7M4 5v6h6m2-4v5l3 2',
    evidence:'M7 4h10v17H4V4h3zm1-1h8v4H8zM7 12l2 2 4-4m-6 7h7',
    warning:'M12 3L2 21h20L12 3zM12 9v5M12 17h.01',
    check:'M5 12l4 4L20 5', close:'M6 6l12 12M6 18L18 6',
    clock:'M12 3a9 9 0 1 0 0 18a9 9 0 0 0 0-18M12 7v6l4 2',
    search:'M10 3a7 7 0 1 0 0 14a7 7 0 0 0 0-14M15 15l6 6',
    download:'M12 3v12M7 10l5 5 5-5M4 17v4h16v-4',
    columns:'M3 4h18v16H3zM9 4v16M15 4v16',
    moon:'M20 15A9 9 0 0 1 9 4a9 9 0 1 0 11 11',
    sun:'M12 8a4 4 0 1 0 0 8a4 4 0 0 0 0-8M12 2v2M12 20v2M2 12h2M20 12h2'
  };
  const icon = name => '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + (paths[name] || paths.list) + '"/></svg>';

  const sectionIcons = {
    overview:'grid', collection:'clock', objectQueries:'evidence', zoneQueries:'evidence',
    dcs:'server', servers:'server', system:'chip', disks:'database', paths:'folder', network:'network',
    roles:'crown', role:'shield', time:'clock', certificates:'certificate', shares:'share',
    sites:'pin', subnets:'network', links:'link', linkMembers:'member', bridges:'hierarchy',
    bridgeMembers:'nested', transports:'forward', schedules:'calendar', settings:'sliders',
    forest:'forest', domains:'globe', hierarchy:'hierarchy', levels:'layers', fsmo:'crown',
    suffixes:'text', partitions:'partitions', contexts:'database', containers:'folder', policies:'lock',
    trusts:'shield', directions:'split', partners:'link', connections:'sync',
    client:'monitor', forwarders:'forward', conditional:'split', recursion:'sync', scavenging:'history',
    rootHints:'hierarchy', zones:'globe', aging:'clock', delegations:'share', nameServers:'server',
    nsAddresses:'identity', scopes:'layers', gpos:'document', versions:'history', permissions:'key',
    wmiFilters:'filter', wmiReferences:'link', ous:'folder', counts:'count', inheritance:'hierarchy',
    computers:'monitor', osSummary:'layers', locations:'pin', spns:'key', delegation:'share',
    groups:'users', members:'member', nested:'nested', parents:'parent',
    users:'person', flags:'flag', memberships:'member', primaryGroups:'users',
    departments:'hierarchy', companies:'company', statuses:'status'
  };

  function sectionIcon(key) {
    return meta.inventoryId === 'ADGroup' && key === 'objectQueries' ? 'identity' : sectionIcons[key];
  }

  const layouts = {
    ADInfrastructure: {
      main:'dcs', icon:'server', subtitle:'Browse domain controllers and the configuration collected for each server.',
      cards:[['Domain controllers','dcs'],['AD sites','dcs','Site'],['Operating systems','dcs','OS']],
      charts:[['Operating systems','dcs','OS'],['Controllers by site','dcs','Site']],
      filters:{dcs:['Site','OS','Inventory'],zones:['Type','AD integrated']},
      nav:{'Domain controllers':['dcs','roles'],'System & storage':['system','disks','paths'],'Network & DNS':['network','forwarders','zones','conditional'],'Sites & replication':['subnets','partners','connections'],'Services & security':['time','certificates','shares']}
    },
    ADSitesAndServices: {
      main:'sites', icon:'globe', subtitle:'Explore sites, subnet assignments, transport links and directory server objects.',
      cards:[['AD sites','sites'],['Subnet records','subnets'],['Directory server objects','servers']],
      charts:[['Servers by site','servers','Site'],['Subnet assignments','subnets','Assignment']],
      filters:{subnets:['Assignment','Site'],servers:['Site','NTDS object present'],links:['Transport']},
      nav:{'Topology':['sites','subnets','servers'],'Transport & schedules':['links','linkMembers','bridges','bridgeMembers','settings','transports','schedules']}
    },
    ADForest: {
      main:'domains', icon:'globe', subtitle:'See your forest structure, directory server references, and role assignments.',
      cards:[['Forest domains','domains'],['Unique directory servers','servers'],['Observed FSMO owners','fsmo','Owner']],
      charts:[['Domain hierarchy','hierarchy'],['Directory servers by domain','servers','Domain']],
      filters:{domains:['Functional level','Query status'],fsmo:['Scope','Role']},
      nav:{'Forest & domains':['forest','domains','hierarchy','levels','fsmo','servers'],'Configuration':['suffixes','partitions','contexts','containers','policies']}
    },
    ADTrusts: {
      main:'trusts', icon:'link', subtitle:'Browse trust objects, reported directions, partner references and trust settings.',
      cards:[['Trust objects observed','trusts'],['Partner references','partners'],['Domains in scope','domains']],
      charts:[['Trust directions','trusts','Direction'],['Trust objects by domain','trusts','Observed domain']],
      filters:{trusts:['Observed domain','Direction'],settings:['Observed domain','Selective authentication reported']},
      nav:{'Trust inventory':['trusts','partners','domains'],'Trust configuration':['directions','settings']}
    },
    ADDns: {
      main:'dcs', icon:'server', subtitle:'Review DNS roles, client resolver settings, forwarding and zone observations by controller.',
      cards:[['Controllers in scope','dcs'],['Zone observations','zones'],['Name server records','nameServers']],
      charts:[['Zone types','zones','Type'],['Zone observations by server','zones','Server']],
      filters:{dcs:['Site','Inventory'],zones:['Server','Type','AD integrated'],nameServers:['Server','Zone']},
      nav:{'DNS servers':['dcs','role','client'],'Forwarding & server settings':['forwarders','conditional','recursion','scavenging','rootHints'],'Zones & name servers':['zones','aging','delegations','nameServers','nsAddresses','scopes']}
    },
    ADGroupPolicy: {
      main:'gpos', icon:'shield', subtitle:'Explore Group Policy objects, stored links, settings structure and reported permissions.',
      cards:[['GPOs observed','gpos'],['Stored links','links'],['Reported permissions','permissions']],
      charts:[['GPO status','gpos','Status'],['Links by container type','links','Container type']],
      filters:{gpos:['Status'],links:['Container type','Link enabled','Enforced'],permissions:['Permission']},
      nav:{'Group Policy':['gpos','links','containers','permissions'],'Policy details':['versions','settings','wmiFilters','wmiReferences']}
    },
    ADOrganizationalUnit: {
      main:'ous', icon:'folder', subtitle:'Browse OU structure, object counts, stored policy links and delegation records.',
      cards:[['Organizational units','ous'],['Stored GPO links','links'],['Delegation entries','delegations']],
      charts:[['Direct users by OU','counts','Name','Direct users'],['Direct computers by OU','counts','Name','Direct computers']],
      filters:{inheritance:['Block GPO inheritance'],delegations:['Access type','Inherited']},
      nav:{'OU inventory':['ous','counts'],'Policy & delegation':['links','inheritance','delegations']}
    },
    ADComputer: {
      main:'computers', icon:'server', subtitle:'Browse directory computer objects, reported operating systems and account configuration.',
      cards:[['Computer objects','computers'],['Directory locations','locations'],['SPN records','spns']],
      charts:[['Reported OS family','computers','OS family'],['Reported server releases','computers','Server release']],
      filters:{computers:['OS family','OS reported','Server release','Version reported','Build reported','Enabled','DC role reported','Location DN']},
      nav:{'Computer inventory':['computers','osSummary','locations'],'Account configuration':['spns','delegation']}
    },
    ADGroup: {
      main:'groups', icon:'users', subtitle:'Group properties, direct member links and collection coverage in one view.',
      cards:[['Directory groups','groups'],['Observed direct member links','members'],['Observed empty member lists','groups','empty']],
      charts:[['Group categories','groups','Category'],['Group scopes','groups','Scope']],
      filters:{groups:['Category','Scope','Membership status'],members:['Member type','Resolution status']},
      nav:{'Group inventory':['groups','members','nested','parents']}
    },
    ADUser: {
      main:'users', icon:'users', subtitle:'Browse directory users, organization summaries, account flags and group references.',
      cards:[['User objects','users'],['Observed group links','memberships'],['Department values','departments']],
      charts:[['Account status','users','Enabled'],['Users by department','departments','Department','Users observed']],
      filters:{users:['Enabled','Department','Company','Location DN'],flags:['Password never expires','Password not required']},
      nav:{'User inventory':['users','departments','companies','locations','statuses'],'Account configuration':['flags','memberships','primaryGroups']}
    }
  };

  const layout = layouts[meta.inventoryId] || {main:Object.keys(sections)[0],cards:[],charts:[],filters:{},nav:{}};
  const groupReport = meta.inventoryId === 'ADGroup';
  const state = {key:'overview', query:'', filters:{}, page:1, size:12, sort:null, descending:false, hidden:new Map(), relation:null, onlyGaps:false, onlyEmpty:false};
  let previousFocus;
  let toastTimer;
  let searchTimer;
  const indices = new Map();
  const collectionBasis = groupReport
    ? rows('groups').map(group => group['Membership status'] || 'Unknown')
    : collection.map(status);
  const successful = collectionBasis.filter(value => value === 'Succeeded').length;
  const skipped = collectionBasis.filter(value => value === 'NotApplicable').length;
  const denominator = collectionBasis.length - skipped;
  const gaps = denominator - successful;
  const metadataUnavailable = groupReport && collection.some(row => row.Name === 'Group enumeration' && status(row) !== 'Succeeded');
  const percent = denominator ? successful / denominator * 100 : null;
  const coverageLabel = groupReport ? 'Membership coverage' : 'Collection coverage';
  const basisLabel = groupReport ? 'group member lists' : 'applicable queries';

  function sectionName(key) { return sections[key]?.[0] || key; }
  function activeKey() { return state.key === 'overview' ? layout.main : state.key; }
  function pill(value) {
    const tone = /^(Succeeded|Complete|Yes)$/i.test(value) ? 'teal' :
      /^(TimedOut|Failed|Partial|NotAttempted|Unknown|Denied)$/i.test(value) ? 'amber' : '';
    return '<span class="tag ' + tone + '">' + escape(value === 'TimedOut' ? 'Timed out' : value === 'NotApplicable' ? 'Not applicable' : value === 'NotAttempted' ? 'Not attempted' : value) + '</span>';
  }

  function renderNav() {
    const nav = {...layout.nav};
    const known = new Set(Object.values(nav).flat());
    nav['Collection evidence'] = Object.keys(sections).filter(key => !known.has(key));
    let html = '<div class="navlabel">WORKSPACE</div>' + navButton('overview','Inventory overview');
    for (const [label, keys] of Object.entries(nav)) {
      const available = keys.filter(key => sections[key]);
      if (!available.length) continue;
      html += '<div class="navlabel">' + escape(label.toUpperCase()) + '</div>';
      html += available.map(key => navButton(key,sectionName(key))).join('');
    }
    html += '<div class="navlabel">REPORT</div><button class="navitem" data-action="help">' + icon('shield') + '<span class="navitem-label">Help &amp; About</span></button>';
    $('#nav').innerHTML = html;
  }

  function navButton(key, label) {
    const count = key === 'overview' ? '' : '<span class="count">' + number(rows(key).length) + '</span>';
    const active = key === state.key;
    return '<button class="navitem ' + (active ? 'active' : '') + '" data-section="' + escape(key) +
      '"' + (active ? ' aria-current="page"' : '') + '>' + icon(sectionIcon(key)) + '<span class="navitem-label">' + escape(label) + '</span>' + count + '</button>';
  }

  function metric(label, value, note, key, symbol, filter = '') {
    return '<button class="metric" data-section="' + escape(key) + '" data-quick="' + filter + '">' +
      '<span class="metrichead">' + escape(label) + '<span class="tileicon">' + icon(symbol) + '</span></span>' +
      '<span class="value"><strong>' + escape(value) + '</strong></span><small>' + escape(note) + '</small></button>';
  }

  function metricCards() {
    const cards = layout.cards.map(([label,key,field], i) => {
      const values = rows(key);
      let count = values.length;
      let note = 'Observed records';
      if (field === 'empty') {
        count = values.filter(row => row['Membership status'] === 'Succeeded' && row['Direct linked members'] === 0).length;
        note = 'Among ' + number(successful) + ' collected group lists';
      } else if (field) {
        count = new Set(values.map(row => row[field]).filter(value => value != null && value !== '').map(value => String(value).toLowerCase())).size;
        note = 'Distinct returned values';
      }
      if (key === 'members' && gaps) note = 'Partial coverage · collected groups only';
      if (!count && coverage[key] === false) count = null;
      return metric(label, number(count), note, key, [layout.icon,'link','folder'][i], field === 'empty' ? 'empty' : '');
    });
    cards.push(metric(coverageLabel, percent === null ? '—' : number(successful) + '/' + number(denominator),
      denominator ? number(gaps) + ' unavailable · ' + basisLabel : 'No applicable evidence returned', 'collection','clock'));
    return '<div class="cards">' + cards.join('') + '</div>';
  }

  function bars(title, key, field, weight) {
    const counts = new Map();
    for (const row of rows(key)) {
      const value = row[field];
      const label = value == null ? 'Unknown' : value === '' ? 'Not set' :
        field === 'Enabled' && typeof value === 'boolean' ? (value ? 'Enabled' : 'Disabled') : text(value);
      const amount = weight ? row[weight] : 1;
      if (!Number.isFinite(amount)) continue;
      counts.set(label, (counts.get(label) || 0) + amount);
    }
    const top = [...counts].sort((a,b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0,5);
    const max = Math.max(1,...top.map(item => item[1]));
    return '<section class="panel"><div class="panelhead"><div><h2>' + escape(title) + '</h2><p>' +
      escape(sectionName(key)) + (counts.size > 5 ? ' · top 5 of ' + number(counts.size) : '') + '</p></div></div>' +
      '<div class="bars">' + (top.length ? top.map(([label,n]) =>
        '<div class="barrow"><span title="' + escape(label) + '">' + escape(label) + '</span><div class="track"><div class="fill" style="width:' +
        (n / max * 100) + '%"></div></div><b>' + number(n) + '</b></div>').join('') : '<p class="faint">No values collected for this summary.</p>') +
      '</div></section>';
  }

  function hierarchy() {
    const domains = rows('hierarchy');
    const lookup = new Map(domains.map(row => [String(row.Name).toLowerCase(),row]));
    function depth(row) {
      const visited = new Set([String(row.Name).toLowerCase()]);
      let parent = String(row['Parent domain'] || '').toLowerCase();
      let level = 0;
      while (lookup.has(parent) && !visited.has(parent)) {
        visited.add(parent); level++;
        parent = String(lookup.get(parent)['Parent domain'] || '').toLowerCase();
      }
      return level;
    }
    const sorted = [...domains].sort((a,b) => Number(b['Forest root']) - Number(a['Forest root']) || depth(a) - depth(b) || a.Name.localeCompare(b.Name));
    return '<section class="panel"><div class="panelhead"><div><h2>Domain hierarchy</h2><p>Parent relationships recorded in the snapshot</p></div></div><div class="tree">' +
      sorted.slice(0,6).map(row => '<div class="treerow ' + (depth(row) ? 'child' : '') + '">' + icon('globe') +
        '<span title="' + escape(row.Name) + '">' + escape(row.Name) + '</span><small>' +
        escape(row['Forest root'] ? 'Forest root' : row['Parent domain'] ? 'Parent: ' + row['Parent domain'] : 'Parent not reported') + '</small></div>').join('') +
      (sorted.length > 6 ? '<button class="textlink" data-section="hierarchy">View all domains →</button>' : '') + '</div></section>';
  }

  function coveragePanel() {
    const displayPercent = percent === null ? '—' : percent.toLocaleString(undefined,{maximumFractionDigits:1}) + '%';
    return '<section class="panel"><div class="panelhead"><div><h2>' + coverageLabel + '</h2><p>Completed ' + basisLabel + ' / applicable total</p></div></div>' +
      '<div class="coverage"><div class="ring" style="--angle:' + ((percent || 0) * 3.6) + 'deg"><div class="ringinside"><b>' +
      displayPercent + '</b><small>COLLECTED</small></div></div><div class="coveragelegend"><p><b>' + number(successful) +
      '</b> collected</p><p><b>' + number(gaps) + '</b> unavailable' + (skipped ? ' · ' + number(skipped) + ' not applicable' : '') +
      '</p><button class="textlink" data-section="collection">View collection ledger →</button></div></div>' +
      (groupReport ? '<p class="legendnote">Direct member lists · excludes metadata and primary groups</p>' : '') + '</section>';
  }

  function overview() {
    const charts = layout.charts.map(([title,key,field,weight]) => field ? bars(title,key,field,weight) : hierarchy());
    let summary = '';
    if (meta.inventoryId === 'ADForest') {
      const forest = rows('forest')[0];
      const gcs = rows('servers').filter(row => String(row['Directory roles'] || '').includes('Global Catalog')).length;
      const roles = rows('fsmo').filter(row => row.Owner).length;
      summary = '<div class="minigrid"><section class="panel compact"><span class="tileicon">' + icon('globe') +
        '</span><div><h2>Forest configuration</h2><p>Functional level: ' + escape(text(forest?.['Functional level'])) +
        '</p></div><span class="num">' + number(forest?.['Site count']) + '<span> sites</span></span></section>' +
        '<section class="panel compact"><span class="tileicon">' + icon('server') +
        '</span><div><h2>Directory roles</h2><p>' + number(roles) + ' of ' + number(rows('fsmo').length) +
        ' FSMO assignments returned.</p></div><span class="num">' + number(gcs) + '<span> GCs observed</span></span></section></div>';
    } else if (groupReport) {
      const groups = rows('groups');
      const managed = groups.filter(row => row['Managed by']).length;
      const locations = new Set(groups.map(row => row['Location DN']).filter(Boolean)).size;
      summary = '<div class="minigrid"><section class="panel compact"><span class="tileicon">' + icon('users') +
        '</span><div><h2>Managed-by references</h2><p>Directory references recorded on group objects.</p></div><span class="num">' + number(managed) +
        '<span> / ' + number(groups.length) + '</span></span></section><section class="panel compact"><span class="tileicon">' + icon('folder') +
        '</span><div><h2>Directory locations</h2><p>Distinct parent locations of observed groups.</p></div><span class="num">' + number(locations) + '</span></section></div>';
    }
    return metricCards() + '<div class="panels">' + charts.join('') + coveragePanel() + '</div>' + summary;
  }

  function coverageNotice() {
    const incomplete = gaps > 0 || metadataUnavailable;
    const title = metadataUnavailable ? 'Group enumeration unavailable' : incomplete
      ? coverageLabel + ' is incomplete · ' + number(successful) + ' of ' + number(denominator) + ' collected'
      : denominator ? 'All applicable ' + (groupReport ? 'member lists' : 'queries') + ' collected' : 'No applicable collection evidence';
    let message = meta.notice || '';
    if (gaps && groupReport) message = number(gaps) + ' group lists are unavailable. Direct membership totals cover collected groups only.';
    if (gaps && !groupReport) message = number(gaps) + ' applicable queries did not complete successfully. See collection evidence for details.';
    if (sample && !message.includes('SAMPLE DATA')) message = 'Fictional sample. ' + message;
    return '<div class="notice ' + (incomplete ? '' : denominator ? 'good' : 'neutral') + '">' +
      icon(incomplete ? 'warning' : denominator ? 'check' : 'list') + '<div><b>' + escape(title) + '</b>' + escape(message) +
      '</div><span class="grow"></span>' + (incomplete ? '<button class="textlink" data-section="collection" data-quick="gaps">Review gaps →</button>' : '') + '</div>';
  }

  const preferredColumns = {
    ADGroup:{groups:['Name','Category','Scope','Location DN','Direct linked members','Membership status'],members:['Member name','Group','Member type','Resolution status']},
    ADForest:{domains:['Name','NetBIOS name','Functional level','Parent domain','Query status'],servers:['Name','Domain','Directory roles','Reference count'],partitions:['Name','DNS root','Enabled']},
    ADUser:{users:['Name','SAM account name','UPN','Department','Enabled']},
    ADComputer:{computers:['Name','DNS hostname','OS reported','OS family','Server release','Enabled']},
    ADInfrastructure:{dcs:['Name','Site','IPv4','OS','GC','Inventory']},
    ADDns:{dcs:['Name','Site','Zones observed','Inventory']}
  };

  function visibleColumns(key) {
    if (!state.hidden.has(key)) {
      const all = sections[key][1];
      const defaults = preferredColumns[meta.inventoryId]?.[key] ||
        all.filter((col,index) => index === 0 || !/(?:^DN$| DN$| ID$| SID$|^GUID$| raw$|base64)/i.test(col)).slice(0,7);
      const keep = new Set(defaults.filter(col => all.includes(col)));
      if (!keep.size) keep.add(all[0]);
      state.hidden.set(key,new Set(all.filter(col => !keep.has(col))));
    }
    return sections[key][1].filter(col => !state.hidden.get(key).has(col));
  }

  function filterFields(key) {
    const schema = sections[key][1];
    const requested = key === 'collection' ? ['Status','Outcome'] : layout.filters[key] || ['Status','Query status','Type'];
    return requested.filter(col => schema.includes(col) && rows(key).some(row => row[col] != null));
  }

  function matching(key) {
    if (!indices.has(key)) indices.set(key,rows(key).map((row,index) => ({row,index})));
    const query = state.query.trim().toLowerCase();
    const filtered = indices.get(key).filter(({row}) => {
      if (state.onlyGaps && ['Succeeded','NotApplicable'].includes(status(row))) return false;
      if (state.onlyEmpty && (row['Membership status'] !== 'Succeeded' || row['Direct linked members'] !== 0)) return false;
      if (state.relation && !state.relation.match(row)) return false;
      for (const [column,value] of Object.entries(state.filters)) {
        if (text(row[column]) !== value) return false;
      }
      return !query || Object.values(row).some(value => text(value).toLowerCase().includes(query));
    });
    if (state.sort) filtered.sort((a,b) => {
      const x = a.row[state.sort], y = b.row[state.sort];
      if (x == null || y == null) return Number(x == null) - Number(y == null);
      const difference = typeof x === 'number' && typeof y === 'number' ? x - y : collator.compare(text(x),text(y));
      return difference * (state.descending ? -1 : 1);
    });
    return filtered;
  }
  const collator = new Intl.Collator(undefined,{numeric:true,sensitivity:'base'});

  function controls(key) {
    const shown = visibleColumns(key);
    const filterHtml = filterFields(key).map(column => {
      const values = [...new Set(rows(key).map(row => text(row[column])))].sort(collator.compare);
      return '<select data-filter="' + escape(column) + '" aria-label="Filter by ' + escape(column) + '">' +
        '<option value="all">All · ' + escape(column) + '</option>' + values.map(value =>
          '<option value="v:' + escape(value) + '"' + (state.filters[column] === value ? ' selected' : '') + '>' +
          escape(value === '' ? 'Not set' : value) + '</option>').join('') + '</select>';
    }).join('');
    const columns = sections[key][1].map(col =>
      '<label><input type="checkbox" data-column="' + escape(col) + '"' + (shown.includes(col) ? ' checked' : '') +
      '> ' + escape(col) + '</label>').join('');
    return '<div class="toolbar"><label class="search">' + icon('search') + '<input type="search" id="query" aria-label="Search records" placeholder="Search records…" value="' +
      escape(state.query) + '"></label>' + filterHtml + '<button class="reset" data-action="reset">Reset</button><span class="grow"></span>' +
      '<details class="columns"><summary class="btn">' + icon('columns') + 'Columns</summary><div class="columnlist">' + columns + '</div></details>' +
      '<button class="btn" data-action="csv">' + icon('download') + 'Filtered CSV</button></div>';
  }

  function shortLocation(value) {
    return String(value || '').match(/^(?:OU|CN)=((?:\\.|[^,])+)/i)?.[1]?.replace(/\\,/g,',') || text(value);
  }

  function grid(key) {
    const filtered = matching(key);
    const cols = visibleColumns(key);
    const pages = Math.max(1,Math.ceil(filtered.length/state.size));
    state.page = Math.min(state.page,pages);
    const offset = (state.page-1)*state.size;
    const th = cols.map(col => '<th scope="col"' + (state.sort === col ? ' aria-sort="' +
      (state.descending ? 'descending' : 'ascending') + '"' : '') + '><button data-sort="' + escape(col) + '">' +
      escape(col === 'Location DN' && key === 'groups' ? 'Location' : col) + ' ' +
      (state.sort === col ? (state.descending ? '↓' : '↑') : '↕') + '</button></th>').join('');
    const body = filtered.slice(offset,offset+state.size).map(({row,index}) => '<tr>' + cols.map((col,i) => {
      const value = row[col];
      const display = col === 'Location DN' && key === 'groups' ? shortLocation(value) : text(value);
      if (i === 0) return '<td><button class="groupname" data-object="' + index + '" data-key="' + escape(key) +
        '" title="' + escape(display) + '"><span class="objicon">' + icon(sectionIcon(key)) +
        '</span><span>' + escape(display) + '</span></button></td>';
      if (/(?:status|outcome|inventory)$/i.test(col) || typeof value === 'boolean') return '<td>' + pill(display) + '</td>';
      return '<td title="' + escape(text(value)) + '">' + escape(display) + '</td>';
    }).join('') + '</tr>').join('');
    const empty = coverage[key] === false && !rows(key).length ? 'Collection unavailable. See the collection ledger.' : 'No matching records.';
    return '<div class="tablewrap"><table><thead><tr>' + th + '</tr></thead><tbody>' + body + '</tbody></table>' +
      (filtered.length ? '' : '<div class="empty">' + empty + '</div>') + '</div><div class="tablefoot"><span role="status">' +
      number(filtered.length ? offset+1 : 0) + '–' + number(Math.min(offset+state.size,filtered.length)) + ' of ' + number(filtered.length) +
      ' records</span><span class="grow"></span><label>Rows <select id="pagesize" aria-label="Rows per page">' +
      [12,25,50,100].map(n => '<option' + (state.size === n ? ' selected' : '') + '>' + n + '</option>').join('') + '</select></label>' +
      '<span>Page ' + number(state.page) + ' of ' + number(pages) + '</span><button class="btn" data-action="prev"' +
      (state.page === 1 ? ' disabled' : '') + '>Previous</button><button class="btn" data-action="next"' +
      (state.page === pages ? ' disabled' : '') + '>Next</button></div>';
  }

  function reportActions() {
    return '<details class="exports"><summary class="btn primary">' + icon('download') + 'Export snapshot</summary><div class="columnlist">' +
      '<button class="btn" data-action="json">Download report JSON</button>' +
      '<a href="' + encodeURIComponent(payload.reportBaseName || 'Inventory') + '.json" download>Full JSON beside this report</a>' +
      '<a href="CSV/' + encodeURIComponent(activeKey()) + '.csv" download>Full section CSV beside this report</a></div></details>';
  }

  function render() {
    const key = activeKey();
    const isOverview = state.key === 'overview';
    const title = isOverview ? meta.title : sectionName(key);
    renderNav();
    $('#crumb').textContent = isOverview ? 'Overview' : title;
    const scope = meta.connectionDomain || meta.domain || meta.forest || meta.scope;
    const context = '<div class="scope"><span><b>Scope</b> ' + escape(meta.scope) + '</span><span class="sep"></span><span>' +
      escape(scope === meta.scope ? (meta.source || 'Directory inventory') : scope) + '</span>' +
      (meta.sourceDC ? '<span class="sep"></span><span><b>Source</b> ' + escape(meta.sourceDC) + '</span>' : '') + '</div>';
    const note = state.relation ? 'Related records · ' + state.relation.label :
      state.onlyGaps ? 'Showing unsuccessful applicable queries' :
      state.onlyEmpty ? 'Showing collected groups with zero direct member links' :
      key === 'collection' ? 'Query status and evidence availability' : 'Select a record to open its properties and related evidence.';
    const limitations = Array.isArray(meta.limitations) ? meta.limitations : [];
    $('#main').innerHTML = '<div class="heading"><div><div class="eyebrow">DIRECTORY / INVENTORY</div><h1>' + escape(title) +
      '</h1><p class="sub">' + escape(layout.subtitle || meta.scope) + '</p></div><span class="grow"></span>' + reportActions() + '</div>' +
      context + coverageNotice() + (isOverview ? overview() : '') +
      '<section class="panel directory"><div class="sectionhead"><div><h2>' + escape(sectionName(key)) + '</h2><p>' +
      escape(note) + '</p></div><span class="grow"></span><span class="tag ' + (coverage[key] === false ? 'amber' : '') + '">' +
      number(rows(key).length) + ' observed' + (coverage[key] === false ? ' · partial or unavailable' : '') +
      '</span></div>' + controls(key) + '<div id="tablearea">' + grid(key) + '</div></section>' +
      (limitations.length ? '<details class="panel method"><summary>Collection scope &amp; interpretation</summary>' +
        limitations.map(line => '<p>' + escape(line) + '</p>').join('') + '</details>' : '') +
      '<footer class="bottom"><span>JP · PSInsightInventory ' + escape(meta.version) + '</span><span>Run ' + escape(meta.run) +
      '</span><span class="grow"></span><span>' + escape(meta.generatedDisplay || meta.generated) + '</span></footer>';
  }

  function related(key,row) {
    const relations = [];
    const add = (target,column,value) => {
      if (!sections[target] || value == null || value === '') return;
      const folded = String(value).toLowerCase();
      const match = item => item[column] != null && String(item[column]).toLowerCase() === folded;
      const count = rows(target).filter(match).length;
      if (count) relations.push({target,match,count});
    };
    const groupId = row['Group ID'];
    if (key === 'groups') {
      add('members','Group ID',groupId);
      add('nested','Parent group ID',groupId);
      add('parents','Group ID',groupId);
      add('collection','Target',row.DN);
    } else if (key === 'dcs') {
      for (const target of Object.keys(sections)) if (target !== key) add(target,meta.inventoryId === 'ADDns' ? 'Server' : 'Name',row.Name);
    } else if (key === 'domains' && meta.inventoryId === 'ADForest') {
      add('servers','Domain',row.Name); add('fsmo','Domain / forest',row.Name); add('policies','Name',row.Name); add('containers','Domain',row.Name);
    } else if (key === 'sites') {
      add('servers','Site',row.Name); add('subnets','Site',row.Name); add('linkMembers','Site',row.Name); add('settings','Site',row.Name);
    } else if (key === 'links' && meta.inventoryId === 'ADSitesAndServices') {
      add('linkMembers','Link DN',row.DN); add('schedules','DN',row.DN);
    } else if (key === 'bridges') {
      add('bridgeMembers','Bridge DN',row.DN);
    } else if (key === 'containers' && meta.inventoryId === 'ADGroupPolicy') {
      add('links','Container DN',row.DN);
    } else if (key === 'wmiFilters') {
      add('wmiReferences','Filter ID',row['Filter ID']);
    } else if (meta.inventoryId === 'ADUser' && ['departments','companies','locations','statuses'].includes(key)) {
      const field = {departments:'Department',companies:'Company',locations:'Location DN',statuses:'Enabled'}[key];
      const match = item => item[field] === row[field];
      const count = rows('users').filter(match).length;
      if (count) relations.push({target:'users',match,count});
    } else if (key === 'osSummary' && meta.inventoryId === 'ADComputer') {
      const columns = ['OS family','OS reported','Server release','Version reported','Build reported'];
      const match = item => columns.every(column => item[column] === row[column]);
      const count = rows('computers').filter(match).length;
      if (count) relations.push({target:'computers',match,count});
    } else {
      for (const id of ['Computer ID','User ID','OU ID','GPO ID']) {
        if (row[id]) for (const target of Object.keys(sections)) if (target !== key && sections[target][1].includes(id)) add(target,id,row[id]);
      }
    }
    return relations;
  }

  let currentDetail = null;
  function openDetail(key,index) {
    const row = rows(key)[index];
    if (!row || !sections[key]) return;
    if ($('#veil').hidden) previousFocus = document.activeElement;
    const relations = related(key,row);
    currentDetail = {key,index,relations,label:row.Name || sectionName(key)};
    $('#drawer').innerHTML = '<div class="drawerhead"><span class="tileicon">' + icon(sectionIcon(key)) +
      '</span><span class="eyebrow" style="margin:0">' + escape(sectionName(key).toUpperCase()) + '</span><span class="grow"></span>' +
      '<button class="btn iconbtn" data-action="close" aria-label="Close details">' + icon('close') + '</button></div><h2 id="detailTitle">' +
      escape(row.Name || sectionName(key)) + '</h2>' +
      '<dl class="props">' + sections[key][1].map(col => '<dt>' + escape(col) + '</dt><dd>' + escape(text(row[col])) + '</dd>').join('') + '</dl>' +
      (relations.length ? '<h3>Related records</h3>' + relations.map(({target,count},i) =>
        '<p class="meta"><button class="textlink" data-related="' + i + '">' + escape(sectionName(target)) + ' · ' + number(count) + ' →</button></p>').join('') : '') +
      schedule(row);
    $('#veil').hidden = false;
    $('#shell').inert = true;
    $('#help').inert = true;
    document.body.style.overflow = 'hidden';
    $('#drawer [data-action="close"]').focus();
  }

  function schedule(row) {
    const masks = row['Hourly masks UTC'];
    if (row['Parse status'] !== 'Parsed' || typeof masks !== 'string' || !/^[0-9a-f]{168}$/i.test(masks)) return '';
    const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    return '<h3>Stored weekly schedule · UTC</h3><div class="tablewrap"><table><thead><tr><th>Day</th>' +
      Array.from({length:24},(_,i) => '<th>' + String(i).padStart(2,'0') + '</th>').join('') +
      '</tr></thead><tbody>' + days.map((day,d) => '<tr><th>' + day + '</th>' +
        Array.from({length:24},(_,h) => {
          const count = [1,2,4,8].filter(bit => (parseInt(masks[d*24+h],16) & bit)).length;
          return '<td class="' + (count ? 'tag teal' : '') + '">' + count + '/4</td>';
        }).join('') + '</tr>').join('') + '</tbody></table></div>';
  }

  function closeDetail() {
    if ($('#veil').hidden) return;
    $('#veil').hidden = true;
    $('#shell').inert = false;
    $('#help').inert = false;
    document.body.style.overflow = '';
    currentDetail = null;
    if (previousFocus?.isConnected) previousFocus.focus();
  }

  function navigate(key,quick = '',relation = null) {
    if (key !== 'overview' && !sections[key]) return;
    clearTimeout(searchTimer);
    closeDetail();
    Object.assign(state,{key,query:'',filters:{},page:1,sort:null,descending:false,relation,onlyGaps:quick === 'gaps',onlyEmpty:quick === 'empty'});
    $('#shell').classList.remove('menuopen');
    $('#menubtn').setAttribute('aria-expanded','false');
    render();
    $('#main').focus();
    window.scrollTo(0,0);
  }

  function download(name,value,type) {
    const url = URL.createObjectURL(new Blob([value],{type}));
    const link = document.createElement('a');
    link.href = url; link.download = name;
    document.body.append(link); link.click(); link.remove();
    setTimeout(() => URL.revokeObjectURL(url),1500);
    clearTimeout(toastTimer);
    $('#toast').textContent = 'Exported ' + name;
    $('#toast').hidden = false;
    toastTimer = setTimeout(() => { $('#toast').hidden = true; },2500);
  }

  function csv() {
    const key = activeKey(), cols = sections[key][1];
    const quote = value => {
      const cell = String(value ?? '');
      const safe = typeof value === 'string' && /^[=+@\-\t\r\n]/.test(cell) ? "'" + cell : cell;
      return '"' + safe.replace(/"/g,'""') + '"';
    };
    const content = [cols.map(quote).join(','),...matching(key).map(({row}) => cols.map(col => quote(row[col])).join(','))];
    download((payload.reportBaseName || 'Inventory') + '-' + key + '-filtered.csv','\ufeff' + content.join('\r\n'),'text/csv;charset=utf-8');
  }

  const refresh = () => { $('#tablearea').innerHTML = grid(activeKey()); };
  document.addEventListener('click',event => {
    const button = event.target.closest('button');
    if (!button) return;
    const d = button.dataset;
    if (d.section) { navigate(d.section,d.quick); return; }
    if (d.object !== undefined) { openDetail(d.key,Number(d.object)); return; }
    if (d.related !== undefined && currentDetail) {
      const relation = currentDetail.relations[Number(d.related)];
      navigate(relation.target,'',{match:relation.match,label:currentDetail.label});
      return;
    }
    if (d.sort) {
      state.descending = state.sort === d.sort && !state.descending;
      state.sort = d.sort; state.page = 1; refresh();
      return;
    }
    switch (d.action) {
      case 'close': closeDetail(); break;
      case 'help': $('#help').open = !$('#help').open; if ($('#help').open) $('#help summary').focus(); break;
      case 'reset': navigate(state.key); break;
      case 'prev': state.page--; refresh(); break;
      case 'next': state.page++; refresh(); break;
      case 'csv': csv(); break;
      case 'json': download((payload.reportBaseName || 'Inventory') + '-Report.json',JSON.stringify(payload),'application/json'); break;
    }
  });
  document.addEventListener('input',event => {
    if (event.target.id === 'query') {
      state.query = event.target.value;
      state.page = 1;
      clearTimeout(searchTimer);
      searchTimer = setTimeout(refresh,120);
    }
  });
  document.addEventListener('change',event => {
    const target = event.target, d = target.dataset;
    if (d.filter) {
      if (target.value === 'all') delete state.filters[d.filter];
      else state.filters[d.filter] = target.value.slice(2);
      state.page = 1; refresh();
    }
    if (target.id === 'pagesize') { state.size = Number(target.value); state.page = 1; refresh(); }
    if (d.column) {
      const key = activeKey(), hidden = state.hidden.get(key);
      if (!target.checked && visibleColumns(key).length === 1) { target.checked = true; return; }
      if (target.checked) hidden.delete(d.column); else hidden.add(d.column);
      refresh();
    }
  });
  document.addEventListener('keydown',event => {
    if (event.key === 'Escape') {
      closeDetail();
      $('#help').open = false;
      $('#shell').classList.remove('menuopen');
      $('#menubtn').setAttribute('aria-expanded','false');
    }
    if (event.key === 'Tab' && !$('#veil').hidden) {
      const items = [...$('#drawer').querySelectorAll('button,a[href]')];
      if (event.shiftKey && document.activeElement === items[0]) { event.preventDefault(); items.at(-1).focus(); }
      else if (!event.shiftKey && document.activeElement === items.at(-1)) { event.preventDefault(); items[0].focus(); }
    }
  });
  $('#veil').onclick = event => { if (event.target === $('#veil')) closeDetail(); };
  $('#menubtn').onclick = () => $('#menubtn').setAttribute('aria-expanded',String($('#shell').classList.toggle('menuopen')));
  $('#theme').innerHTML = icon('moon');
  $('#theme').onclick = () => {
    const dark = document.body.classList.toggle('dark');
    $('#theme').innerHTML = icon(dark ? 'sun' : 'moon');
    $('#theme').setAttribute('aria-label',dark ? 'Switch to light theme' : 'Switch to dark theme');
  };
  document.title = meta.title + ' · PSInsightInventory';
  $('#version').textContent = meta.version;
  $('#source').textContent = sample ? 'SAMPLE DATA' : 'LIVE SNAPSHOT';
  $('#generated').textContent = meta.generatedDisplay || meta.generated;
  $('#sideScope').textContent = (meta.connectionDomain || meta.domain || meta.forest || meta.scope) + ' · v' + meta.version;
  render();
  $('#shell').hidden = false;
})();
