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
	import { DownloadIcon, GithubIcon, SearchIcon } from '@/icons';
	import { search } from '@/search.svelte';
	import { site } from '@/site';
	import { theme } from '@/theme.svelte';

	injectAnalytics({ mode: dev ? 'development' : 'production' });

	let { children } = $props();

	const path = $derived(page.url.pathname);
	const canonical = $derived(site.url + (path === '/' ? '' : path));
	const inDocs = $derived(path === '/docs' || path.startsWith('/docs/'));

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
		// moving between docs pages swaps only the article; a cross-fade of the whole page would flash the sidebar
		if (navigation.from?.url.pathname.startsWith('/docs') && navigation.to?.url.pathname.startsWith('/docs')) return;
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

<!-- the whole site is one rounded panel on the page, like a window: header, content and footer inside it -->
<div class="min-h-dvh w-full p-1.5 sm:p-3">
	<div class="flex min-h-[calc(100dvh-0.75rem)] flex-col overflow-clip rounded-[20px] border border-border bg-plate shadow-[0_1px_3px_rgb(0_0_0/0.04)] sm:min-h-[calc(100dvh-1.5rem)]">
		<header class="flex h-14 items-center gap-2 border-b border-border px-4 sm:px-5" style:view-transition-name="topbar">
			<a href="/" class="me-auto flex shrink-0 items-center gap-2.5 rounded-[9px]" aria-label="mielwm, home">
				<img src="/icon-128.png" alt="" width="28" height="28" class="size-7 rounded-[7px] outline-none" />
				<span class="text-base font-medium tracking-[-0.01em] text-strong">mielwm</span>
			</a>
			<nav aria-label="Site" class="flex items-center gap-1.5">
				<a
					href="/docs"
					aria-current={inDocs ? 'page' : undefined}
					class="nav-item press h-8 rounded-[9px] px-3 text-sm"
				>
					Docs
				</a>
				<button
					type="button"
					onclick={() => (search.open = true)}
					class="press hidden h-8 w-56 items-center gap-2 rounded-[10px] border border-border bg-page/60 ps-2.5 pe-1.5 text-sm text-subtle hover:text-strong focus-visible:shadow-[var(--focus-ring)] focus-visible:outline-none md:flex"
				>
					<Icon icon={SearchIcon} size={13} />
					<span class="me-auto">Search</span>
					<kbd class="key text-xs">⌘K</kbd>
				</button>
				<Button variant="ghost" size="icon" class="size-8 text-subtle hover:text-strong md:hidden" aria-label="Search the docs" onclick={() => (search.open = true)}>
					<Icon icon={SearchIcon} size={15} />
				</Button>
				<Button variant="ghost" size="icon" href={site.repo} target="_blank" rel="noreferrer" class="size-8 text-subtle hover:text-strong" aria-label="mielwm on GitHub">
					<Icon icon={GithubIcon} size={16} />
				</Button>
				<ThemeToggle />
				<Button href={site.download} size="sm" class="ms-1.5 hidden ps-2.5 sm:inline-flex">
					<Icon icon={DownloadIcon} size={14} />
					Download
				</Button>
			</nav>
		</header>

		<div class="flex flex-1 flex-col">
			{@render children()}
		</div>

		<footer class="border-t border-border" style:view-transition-name="footer">
			<div class="flex h-14 items-center justify-between gap-6 px-4 text-xs text-subtle sm:px-5">
				<span>MIT licensed. Made by <a class="link" href="https://miel.my" target="_blank" rel="noreferrer">mielsense</a>.</span>
				<nav aria-label="Elsewhere" class="flex items-center gap-4">
					<a href="/docs" class="hover:text-strong">Docs</a>
					<a href={site.releases} target="_blank" rel="noreferrer" class="hover:text-strong">Releases</a>
					<a href={site.repo} target="_blank" rel="noreferrer" class="hover:text-strong">GitHub</a>
				</nav>
			</div>
		</footer>
	</div>
</div>

<Search />
