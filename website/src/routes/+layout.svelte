<script lang="ts">
	import '../app.css';
	import { dev } from '$app/environment';
	import { beforeNavigate, onNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import { Button } from '@mielui/svelte/components/button';
	import { injectAnalytics } from '@vercel/analytics/sveltekit';
	import Icon from '@/components/Icon.svelte';
	import Search from '@/components/Search.svelte';
	import ThemeToggle from '@/components/ThemeToggle.svelte';
	import { DownloadIcon, GithubIcon } from '@/icons';
	import { site } from '@/site';
	import { theme } from '@/theme.svelte';

	injectAnalytics({ mode: dev ? 'development' : 'production' });

	let { children } = $props();

	const path = $derived(page.url.pathname);
	const canonical = $derived(site.url + (path === '/' ? '' : path));
	// an error page under /docs has no docs sidebar, so it keeps the site nav
	const inDocs = $derived(!page.error && (path === '/docs' || path.startsWith('/docs/')));
	// the landing page sits in a centred column; the docs run edge to edge
	const gutter = $derived(inDocs ? 'px-4 sm:px-5' : 'wrap');

	// The browser's own chrome follows the theme the visitor picked, not only their system setting.
	$effect(() => {
		const color = theme.dark ? '#0e0e0e' : '#f5f5f5';
		for (const meta of document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')) meta.content = color;
	});

	// Smooth page scrolling with the mouse wheel. Touch scrolling is native either way, so phones skip it.
	$effect(() => {
		if (matchMedia('(prefers-reduced-motion: reduce), (pointer: coarse)').matches) return;
		let lenis: import('lenis').default | undefined;
		let gone = false;
		import('lenis').then(({ default: Lenis }) => {
			if (!gone) lenis = new Lenis({ autoRaf: true, allowNestedScroll: true, anchors: { offset: -24 } });
		});
		return () => {
			gone = true;
			lenis?.destroy();
		};
	});

	// The reveal animations belong to the first page load only.
	beforeNavigate(() => document.documentElement.classList.add('revealed'));

	onNavigate((navigation) => {
		if (!document.startViewTransition || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
		// only the move between the landing page and the docs animates; between docs pages only the article
		// changes, and animating the whole page would flash the sidebar
		const docs = (url?: URL) => url?.pathname === '/docs' || !!url?.pathname.startsWith('/docs/');
		const from = navigation.from?.url, to = navigation.to?.url;
		if (!((from?.pathname === '/' && docs(to)) || (docs(from) && to?.pathname === '/'))) return;
		return new Promise((resolve) => {
			document.startViewTransition(async () => {
				resolve();
				await navigation.complete;
			});
		});
	});

	const software = JSON.stringify({
		'@context': 'https://schema.org',
		'@type': 'SoftwareApplication',
		name: site.name,
		description: site.description,
		url: site.url,
		applicationCategory: 'UtilitiesApplication',
		operatingSystem: 'macOS 15 or later',
		downloadUrl: site.download,
		license: 'https://opensource.org/licenses/MIT',
		offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' }
	});
</script>

<svelte:head>
	<link rel="icon" href="/favicon.png" type="image/png" />
	<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
	<link rel="canonical" href={canonical} />
	<meta name="color-scheme" content="light dark" />
	<meta property="og:type" content="website" />
	<meta property="og:site_name" content={site.name} />
	<meta property="og:url" content={canonical} />
	<meta property="og:image" content="{site.url}/og.jpg" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta property="og:image:alt" content="The mielwm overview: every window on one canvas, seen through a curved lens." />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:image" content="{site.url}/og.jpg" />
	{@html `<script type="application/ld+json">${software}</script>`}
</svelte:head>

<!-- the page itself is the background: no frame. The landing page sits in a centred column with a bare nav;
     the docs have no header at all, their sidebar holds the logo, search and tools -->
<div class="flex min-h-dvh flex-col">
	{#if !inDocs}
		<header>
			<div class="wrap flex h-16 items-center gap-2">
				<a href="/" class="brand me-auto flex shrink-0 items-center gap-2.5 rounded-[9px]" aria-label="mielwm, home">
					<img src="/icon-128.png" alt="" width="28" height="28" class="size-7 rounded-[7px] outline-none" />
					<span class="text-base font-medium tracking-[-0.01em] text-strong">mielwm</span>
				</a>
				<nav aria-label="Site" class="flex items-center gap-1.5">
					<a href="/docs" class="nav-item press h-8 rounded-[9px] px-3 text-sm">Docs</a>
					<Button variant="ghost" size="icon" href={site.repo} target="_blank" rel="noreferrer" class="size-8 text-subtle hover:text-strong" aria-label="mielwm on GitHub">
						<Icon icon={GithubIcon} size={16} />
					</Button>
					<ThemeToggle />
					<Button href={site.download} size="sm" class="ms-1.5 hidden ps-2.5 sm:inline-flex">
						<Icon icon={DownloadIcon} size={14} />
						Download
					</Button>
				</nav>
			</div>
		</header>
	{/if}

	<div class="flex flex-1 flex-col">
		{@render children()}
	</div>

	<footer>
		<div class="flex h-16 items-center justify-between gap-6 text-xs text-subtle {gutter}">
			<span>MIT licensed. Made by <a class="link" href="https://miel.my" target="_blank" rel="noreferrer">mielsense</a>.</span>
			<nav aria-label="Elsewhere" class="flex items-center gap-4">
				<a href="/docs" class="hover:text-strong">Docs</a>
				<a href={site.releases} target="_blank" rel="noreferrer" class="hover:text-strong">Releases</a>
				<a href={site.repo} target="_blank" rel="noreferrer" class="hover:text-strong">GitHub</a>
			</nav>
		</div>
	</footer>
</div>

<Search />
