<script lang="ts">
	import { Badge } from '@mielui/svelte/components/badge';
	import { Button } from '@mielui/svelte/components/button';
	import { CodeBlock } from '@mielui/svelte/components/code-block';
	import Icon from '@/components/Icon.svelte';
	import Shot from '@/components/Shot.svelte';
	import Sticker from '@/components/Sticker.svelte';
	import { ArrowUpRightIcon, BookIcon, ChartIcon, ChevronLeftIcon, ChevronRightIcon, CommandIcon, DownloadIcon, GithubIcon, LayersIcon, SearchIcon, SparkleIcon, TerminalIcon, WrenchIcon, type IconData } from '@/icons';
	import { mesh } from '@/mesh';
	import { site } from '@/site';

	// screenshot sizes, from the source files in scripts/images.sh
	const wide = { width: 3600, height: 2188 };
	const desktop = { width: 3600, height: 2338 };
	const settings = { width: 1430, height: 1280 };

	const keys = [
		{ keys: ['⌃⌥G'], does: 'Zoom out to every window, and back' },
		{ keys: ['⌥1', '⌥9'], does: 'Go to a workspace' },
		{ keys: ['⌥⇧1', '⌥⇧9'], does: 'Send the window there and follow it' },
		{ keys: ['⌥/'], does: 'Tile, and flip the split' },
		{ keys: ['⌥,'], does: 'Stack the workspace' },
		{ keys: ['⌥.'], does: 'Float the window' },
		{ keys: ['⌥Tab'], does: 'Back to the last window, or hold for the list' },
		{ keys: ['⌥T'], does: 'Fill the screen, keeping the gaps' }
	];

	const numbers = [
		{ value: '0.01%', label: 'CPU at idle', detail: 'Share of one core over 30 seconds' },
		{ value: '89 MB', label: 'Memory at rest', detail: 'Physical footprint, 8 windows managed' },
		{ value: '1 frame', label: 'Overview, nothing moving', detail: 'Drawn once in 10 seconds, down from 1200' }
	];

	const build = `git clone https://github.com/mielsense/mielwm.git
cd mielwm
scripts/build-app.sh --install`;


	const lean = 'transition-transform duration-150 ease-out group-hover:translate-x-0.5 motion-reduce:transition-none';
	const leanOut = `${lean} group-hover:-translate-y-0.5`;
	// the text half of a feature card; with the card's 8px inset it sits 24px in on phones, 32px on wider screens
	const copy = 'flex flex-col gap-4 p-4 pb-6 sm:p-6 sm:pb-8';
	const title = 'display text-3xl sm:text-4xl';
</script>

<svelte:head>
	<title>mielwm · a tiling window manager for macOS</title>
	<meta name="description" content={site.description} />
	<meta property="og:title" content="mielwm · a tiling window manager for macOS" />
	<meta property="og:description" content={site.description} />
</svelte:head>

<!-- a section label with a small tilted sticker that springs upright when its section is hovered, from miel.my -->
{#snippet label(text: string, icon: IconData, bg: string)}
	<p class="flex items-center gap-2 text-sm font-medium text-strong">
		<Sticker {icon} {bg} />
		{text}
	</p>
{/snippet}


{#snippet more(href: string, text: string)}
	<a {href} class="group inline-flex items-center gap-1 self-start text-sm text-strong">
		<span class="underline decoration-border-strong decoration-1 underline-offset-4 group-hover:decoration-current">{text}</span>
		<Icon icon={ChevronRightIcon} size={13} class={lean} />
	</a>
{/snippet}

<main>
	<!-- hero -->
	<section class="group/section wrap flex flex-col gap-12 pt-12 pb-16 sm:gap-16 sm:pt-20 sm:pb-20">
		<div class="stagger flex max-w-[46rem] flex-col gap-5">
			<img src="/icon-128.png" alt="" width="64" height="64" class="size-16 rounded-[15px] shadow-[0_4px_14px_rgb(0_0_0/0.18)]" />
			<h1 class="display text-5xl sm:text-6xl lg:text-7xl">Every window on one <span class="accent">endless</span> canvas</h1>
			<p class="max-w-[38rem] text-lg leading-relaxed text-subtle">
				mielwm is a tiling window manager for macOS. Workspaces tile the way AeroSpace does, and when you lose track of something, the
				view pulls back to show every window at once.
			</p>
			<div class="flex flex-wrap items-center gap-2">
				<Button href={site.download} size="lg" class="ps-4">
					<Icon icon={DownloadIcon} size={16} />
					Download for macOS
				</Button>
				<Button href="/docs" variant="glow" size="lg" class="glow-plain ps-4">
					<Icon icon={BookIcon} size={15} />
					Read the docs
				</Button>
			</div>
			<p class="text-sm text-subtle">Free and open source. macOS 15 or later, Apple silicon.</p>
		</div>
		<!-- the lavender mesh drifts slowly behind the overview -->
		<div class="grain dusk rounded-[24px] p-3 sm:p-8 lg:p-12" data-rise>
			<div class="overflow-hidden rounded-[12px] shadow-[0_0_0_1px_rgb(0_0_0/0.14),0_30px_70px_-20px_rgb(20_10_80/0.55)]">
				<Shot name="overview" widths={[2200, 1200]} {...wide} priority sizes="(min-width: 88rem) 77rem, (min-width: 64rem) calc(100vw - 11rem), (min-width: 40rem) calc(100vw - 8rem), calc(100vw - 4rem)" alt="The overview: windows from every workspace laid out on the canvas, the focused one outlined, the capsule search field on top." />
			</div>
		</div>
	</section>

	<!-- the features: quiet cards, a wide one, then pairs of uneven widths -->
	<div class="wrap grid grid-cols-[minmax(0,1fr)] gap-3 sm:gap-4 lg:grid-cols-12">
		<section class="tile group/section grid grid-cols-[minmax(0,1fr)] gap-2 p-2 lg:col-span-12 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]" aria-labelledby="workspaces">
			<div class="{copy} justify-center lg:p-8">
				{@render label('Workspaces', LayersIcon, mesh.violet)}
				<h2 id="workspaces" class={title}>Nine workspaces, three ways to hold a window</h2>
				<p class="text-base leading-relaxed">
					Workspaces 1 to 9 sit side by side, so <kbd class="key">⌥3</kbd> always lands in the same place. Each one tiles its windows, stacks
					them at full size like AeroSpace's accordion, or lets a window float wherever you put it.
				</p>
				<ul class="flex flex-col gap-2 text-base">
					<li class="flex items-center gap-3"><kbd class="key">⌥/</kbd><span>Tiles split the screen, with gaps you set</span></li>
					<li class="flex items-center gap-3"><kbd class="key">⌥,</kbd><span>A stack shows one window at a time</span></li>
					<li class="flex items-center gap-3"><kbd class="key">⌥.</kbd><span>Floating keeps its size and place</span></li>
				</ul>
				<div class="flex flex-col gap-2">
					<div class="w-full max-w-[21rem] overflow-hidden rounded-[12px]">
						<Shot name="strip" widths={[840]} width={840} height={170} sizes="21rem" alt="The stack strip: four app icons, the front window's title, and 2 of 4." />
					</div>
					<p class="text-sm text-subtle">Go to a stack and a strip at its top shows its windows and which one is in front.</p>
				</div>
				{@render more('/docs/workspaces', 'Workspaces')}
			</div>
			<Shot stage={mesh.sky} name="desktop" widths={[1600, 900]} {...desktop} sizes="(min-width: 88rem) 44rem, (min-width: 64rem) 50vw, calc(100vw - 5rem)" alt="Two windows tiled side by side: a browser and a terminal." />
		</section>

		<section class="tile group/section flex flex-col p-2 lg:col-span-7" aria-labelledby="overview">
			<div class={copy}>
				{@render label('The overview', SearchIcon, mesh.indigo)}
				<h2 id="overview" class={title}>Lost a window? <span class="accent">Zoom out</span></h2>
				<p class="text-base leading-relaxed">
					<kbd class="key">⌃⌥G</kbd> pulls the view back through a curved lens. Every window shows as a live picture, wherever it sits on the
					canvas. Type a few letters of a title or an app and press <kbd class="key">Return</kbd> to go there, or
					<kbd class="key">⇧Return</kbd> to bring it to you.
				</p>
				<p class="text-base leading-relaxed text-subtle">
					The search field is a capsule of Liquid glass, like Spotlight. The canvas draws with Metal from ScreenCaptureKit pictures, and your
					windows stay ordinary macOS windows the whole time.
				</p>
				{@render more('/docs/overview', 'The overview')}
			</div>
			<Shot stage={mesh.pink} class="flex-1" name="search" widths={[1600, 900]} {...wide} sizes="(min-width: 88rem) 43rem, (min-width: 64rem) 49vw, calc(100vw - 5rem)" alt="The overview with a search for e, listing Terminal, Code, Notes, TextEdit, Safari and Mail windows, with how far away each one is." />
		</section>

		<section class="tile group/section flex flex-col p-2 lg:col-span-5" aria-labelledby="swipes">
			<div class={copy}>
				{@render label('Trackpad', SparkleIcon, mesh.teal)}
				<h2 id="swipes" class={title}>Three fingers to the next workspace</h2>
				<p class="text-base leading-relaxed">
					Swipe left or right and the trackpad clicks under your fingers as the workspace changes. A pill at the bottom of the display shows
					where you landed.
				</p>
				<div class="flex items-center gap-4">
					<div class="w-40 shrink-0 overflow-hidden rounded-[10px]">
						<Shot name="pill" widths={[460]} width={460} height={160} sizes="10rem" alt="The workspace pill: 1, 2, 3, 5 and 9, with 3 filled." />
					</div>
					<p class="text-sm text-subtle">The workspaces that have windows, the current one filled. The menu bar item can show the same numbers.</p>
				</div>
				{@render more('/docs/trackpad', 'Trackpad and mouse')}
			</div>
			<!-- a drawing: workspaces in their row, the current one outlined, three fingertips under it -->
			<div class="grain flex flex-1 flex-col items-center justify-center gap-8 rounded-[16px] px-4 py-10 text-white sm:px-6" style:background={mesh.teal} aria-hidden="true">
				<div class="flex w-full max-w-[28rem] items-end justify-center gap-1.5 sm:gap-2.5">
					{#each [1, 2, 3, 4, 5] as n (n)}
						<div class="flex min-w-0 flex-1 flex-col items-center gap-2 {n === 3 ? '' : 'opacity-60'}">
							<div class="flex aspect-[16/10] w-full gap-1 rounded-[8px] bg-white/25 p-1.5 shadow-[0_6px_16px_-6px_rgb(0_60_70/0.5)] {n === 3 ? 'ring-2 ring-white' : ''}">
								<span class="flex-1 rounded-[3px] bg-white/85"></span>
								{#if n !== 2}<span class="flex-1 rounded-[3px] bg-white/55"></span>{/if}
								{#if n === 4}<span class="flex-1 rounded-[3px] bg-white/55"></span>{/if}
							</div>
							<span class="text-xs font-medium tabular-nums">{n}</span>
						</div>
					{/each}
				</div>
				<div class="flex items-center gap-4">
					<Icon icon={ChevronLeftIcon} size={16} />
					<div class="flex h-20 w-32 items-center justify-center gap-2.5 rounded-[14px] bg-white/20 shadow-[inset_0_0_0_1px_rgb(255_255_255/0.35)]">
						{#each [0, 1, 2] as i (i)}<span class="size-4 rounded-full bg-white/90 shadow-[0_0_0_5px_rgb(255_255_255/0.18)]"></span>{/each}
					</div>
					<Icon icon={ChevronRightIcon} size={16} />
				</div>
			</div>
		</section>

		<section class="tile group/section flex flex-col p-2 lg:col-span-5" aria-labelledby="settings">
			<div class={copy}>
				{@render label('Settings', WrenchIcon, mesh.sun)}
				<h2 id="settings" class={title}>A real Settings window</h2>
				<p class="text-base leading-relaxed">
					Eleven panes, grouped the way System Settings groups them. The search field in the sidebar finds any setting by name, the gaps
					redraw on a small desktop as you type, and every change reaches your windows right away.
				</p>
				{@render more('/docs/settings', 'Every setting')}
			</div>
			<Shot stage={mesh.orange} class="flex-1" name="settings" widths={[1000]} {...settings} sizes="(min-width: 88rem) 28rem, 90vw" alt="Settings, Layout pane: pictures to pick the layout and orientation of new windows, and the Peek edges slider for stacks." />
		</section>

		<section class="tile group/section flex flex-col p-2 lg:col-span-7" aria-labelledby="aerospace">
			<div class={copy}>
				{@render label('Coming from AeroSpace', TerminalIcon, mesh.coral)}
				<h2 id="aerospace" class={title}>Your keys already work</h2>
				<p class="text-base leading-relaxed">
					The default shortcuts are AeroSpace's wherever it has the same action. Import from AeroSpace reads your
					<code class="rounded-[6px] bg-selected px-1.5 py-0.5 font-mono text-[0.9em] text-strong">aerospace.toml</code> and brings over the
					gaps, the layout, the app rules and the key bindings, after showing you what it found.
				</p>
				<div class="flex flex-col gap-1.5 border-s-2 border-border ps-3.5">
					<span class="flex items-center gap-2 text-base text-strong">Your menu bar app <Badge variant="secondary">New</Badge></span>
					<span class="text-sm text-subtle">Any AeroSpace-compatible menu bar shows mielwm's workspaces and switches on click, with no plugin to install.</span>
				</div>
				{@render more('/docs/aerospace', 'Coming from AeroSpace')}
			</div>
			<div class="grain flex flex-1 items-center justify-center rounded-[16px] px-6 py-10" style:background={mesh.coral}>
				<div class="w-full max-w-[18rem] overflow-hidden rounded-[10px] shadow-[0_0_0_1px_rgb(0_0_0/0.12),0_18px_40px_-12px_rgb(0_0_0/0.45)]">
					<Shot name="import" widths={[520]} width={520} height={640} sizes="18rem" alt="The Import from AeroSpace sheet, listing the gaps, layout and rules it found." />
				</div>
			</div>
		</section>
	</div>

	<!-- keyboard -->
	<section class="group/section wrap grid grid-cols-[minmax(0,1fr)] items-center gap-10 py-16 sm:py-24 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-16" aria-labelledby="keys">
		<div class="flex flex-col gap-4">
			{@render label('Keyboard first', CommandIcon, mesh.lime)}
			<h2 id="keys" class={title}>Your hands stay on the keys</h2>
			<p class="text-base leading-relaxed">Everything has a shortcut, and every shortcut can be changed in Settings. These are the ones you'll use most.</p>
			<ul class="flex flex-col">
				{#each keys as row (row.does)}
					<li class="flex items-center gap-4 border-t border-border py-2.5 first:border-t-0">
						<span class="flex w-28 shrink-0 items-center gap-1.5 text-subtle">
							<kbd class="key text-base">{row.keys[0]}</kbd>
							{#if row.keys[1]}<span aria-label="to">…</span><kbd class="key text-base">{row.keys[1]}</kbd>{/if}
						</span>
						<span class="text-base text-strong">{row.does}</span>
					</li>
				{/each}
			</ul>
			{@render more('/docs/keyboard', 'Every key')}
		</div>
		<div class="flex flex-col gap-3">
			<Shot stage={mesh.lime} name="switcher" widths={[1600, 900]} {...wide} sizes="(min-width: 88rem) 42rem, (min-width: 64rem) 48vw, calc(100vw - 4rem)" alt="The window switcher over two tiled windows: a row of app icons with Terminal selected and its window's title below." />
			<p class="text-sm text-subtle">Hold <kbd class="key">⌥</kbd> and tap <kbd class="key">Tab</kbd> for the switcher. Let go to switch.</p>
		</div>
	</section>

	<!-- performance -->
	<section class="group/section wrap flex flex-col gap-8 pb-16 sm:pb-24" aria-labelledby="performance">
		<div class="flex flex-col gap-6 sm:flex-row sm:items-end sm:justify-between">
			<div class="flex max-w-[40rem] flex-col gap-4">
				{@render label('Performance', ChartIcon, mesh.sky)}
				<h2 id="performance" class={title}>Light when you're not looking</h2>
				<p class="text-base leading-relaxed">
					mielwm sleeps until something changes. The overview only redraws when a window does. Measured on an M3 Pro with
					<code class="rounded-[6px] bg-selected px-1.5 py-0.5 font-mono text-[0.9em] text-strong">scripts/benchmark.sh</code>.
				</p>
			</div>
			{@render more('/docs/performance', 'The full numbers')}
		</div>
		<dl class="tile grid sm:grid-cols-3">
			{#each numbers as stat (stat.label)}
				<div class="flex flex-col gap-1 border-t border-border p-6 first:border-t-0 sm:border-t-0 sm:border-s sm:p-8 sm:first:border-s-0">
					<dt class="order-2 text-base text-strong">{stat.label}</dt>
					<dd class="order-1 mb-2 text-5xl font-medium tracking-[-0.035em] text-strong tabular-nums">{stat.value}</dd>
					<dd class="order-3 text-sm text-subtle">{stat.detail}</dd>
				</div>
			{/each}
		</dl>
	</section>

	<!-- download -->
	<section id="download" class="group/section wrap grid grid-cols-[minmax(0,1fr)] gap-12 pb-16 sm:pb-24 lg:grid-cols-2 lg:gap-16" aria-labelledby="get">
		<!-- the warm card from miel.my's booking section: deep warm ink on an orange mesh (white type fell under 4.5:1 on its yellow), a lit white button -->
		<div class="grain sunrise flex min-h-[22rem] flex-col justify-between gap-10 rounded-[24px] sm:min-h-[26rem] p-6 text-[#2b1000] sm:p-8">
			<img src="/icon-128.png" alt="" width="64" height="64" class="size-16 rounded-[15px] shadow-[0_8px_24px_rgb(120_30_0/0.35)] outline-none" loading="lazy" />
			<div class="flex flex-col gap-6">
				<div class="flex flex-col gap-2">
					<h2 id="get" class="text-5xl leading-[1.02] font-medium tracking-[-0.035em] text-balance text-[#2b1000]">Get mielwm</h2>
					<p class="text-base text-[#3b1600]">Free and MIT licensed. Quitting it puts every window back on screen.</p>
				</div>
				<Button variant="glow" href={site.download} class="group glow-white h-12 w-full justify-between rounded-[12px] ps-4 pe-3.5 text-base">
					<span class="flex items-center gap-2"><Icon icon={DownloadIcon} size={16} />Download mielwm.dmg</span>
					<span class="hidden text-sm text-[#5d5d5d] sm:inline">macOS 15+, Apple silicon</span>
				</Button>
				<div class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm">
					<a href={site.repo} target="_blank" rel="noreferrer" class="group inline-flex items-center gap-1.5 font-medium text-[#2b1000] decoration-1 underline-offset-4 hover:underline">
						<Icon icon={GithubIcon} size={14} />Source on GitHub<Icon icon={ArrowUpRightIcon} size={12} class={leanOut} />
					</a>
					<a href={site.releases} target="_blank" rel="noreferrer" class="group inline-flex items-center gap-1.5 font-medium text-[#2b1000] decoration-1 underline-offset-4 hover:underline">
						Every release<Icon icon={ArrowUpRightIcon} size={12} class={leanOut} />
					</a>
				</div>
			</div>
		</div>
		<div class="flex flex-col justify-center gap-10">
			<div class="flex flex-col gap-3">
				<h3 class="text-lg">The first time you open it</h3>
				<p class="text-sm leading-relaxed text-subtle">mielwm is signed but not notarized by Apple, so macOS stops the first open. You only do this once.</p>
				<ol class="flex flex-col gap-2.5 text-base">
					<li class="flex gap-3"><span class="key shrink-0 text-xs">1</span><span>Open <strong class="font-medium text-strong">mielwm.dmg</strong> and drag mielwm into Applications.</span></li>
					<li class="flex gap-3"><span class="key shrink-0 text-xs">2</span><span>Open mielwm. macOS says it can't check the developer.</span></li>
					<li class="flex gap-3"><span class="key shrink-0 text-xs">3</span><span>Go to System Settings &gt; Privacy &amp; Security and choose <strong class="font-medium text-strong">Open Anyway</strong>.</span></li>
					<li class="flex gap-3"><span class="key shrink-0 text-xs">4</span><span>Allow Accessibility and Screen Recording when mielwm asks.</span></li>
				</ol>
			</div>
			<div class="flex flex-col gap-3">
				<h3 class="text-lg">Or build it yourself</h3>
				<p class="text-sm text-subtle">With the Command Line Tools installed. Xcode isn't needed.</p>
				<CodeBlock code={build} lang="sh" copy="overlay" />
			</div>
		</div>
	</section>
</main>
