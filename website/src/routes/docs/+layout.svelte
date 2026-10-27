<script lang="ts">
	import { afterNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import { Button } from '@mielui/svelte/components/button';
	import Icon from '@/components/Icon.svelte';
	import Sticker from '@/components/Sticker.svelte';
	import ThemeToggle from '@/components/ThemeToggle.svelte';
	import { groupLook, pageIcon } from '@/docs-look';
	import { BookIcon, ChevronDownIcon, DownloadIcon, GithubIcon, SearchIcon } from '@/icons';
	import { search } from '@/search.svelte';
	import { site } from '@/site';

	let { data, children } = $props();

	const path = $derived(page.url.pathname);
	const current = $derived(data.groups.flatMap((group) => group.pages).find((p) => path === `/docs/${p.slug}`));

	// on narrow screens the page list folds away behind a button and folds again after a link
	let menuOpen = $state(false);
	afterNavigate(() => (menuOpen = false));
</script>

{#snippet nav()}
	<a href="/docs" aria-current={path === '/docs' ? 'page' : undefined} class="nav-item press-soft mb-5 h-8 gap-2.5 px-2.5 text-sm">
		<Icon icon={BookIcon} size={14} class="opacity-70" />
		Overview
	</a>
	{#each data.groups as group (group.title)}
		{@const look = groupLook(group.title)}
		<section class="group/section mb-5" aria-labelledby="nav-{group.title}">
			<h2 id="nav-{group.title}" class="mb-1.5 flex items-center gap-2 px-2 text-xs font-medium text-strong">
				<Sticker icon={look.icon} bg={look.mesh} size={18} />
				{group.title}
			</h2>
			<ul class="flex flex-col gap-px">
				{#each group.pages as item (item.slug)}
					<li>
						<a href="/docs/{item.slug}" aria-current={path === `/docs/${item.slug}` ? 'page' : undefined} class="nav-item press-soft h-8 gap-2.5 px-2.5 text-sm">
							<Icon icon={pageIcon(item.slug)} size={14} class="opacity-70" />
							{item.title}
						</a>
					</li>
				{/each}
			</ul>
		</section>
	{/each}
{/snippet}

{#snippet home()}
	<a href="/" class="brand me-auto flex shrink-0 items-center gap-2.5 rounded-[9px]" aria-label="mielwm, home">
		<img src="/icon-128.png" alt="" width="28" height="28" class="size-7 rounded-[7px] outline-none" />
		<span class="text-base font-medium tracking-[-0.01em] text-strong">mielwm</span>
	</a>
{/snippet}

{#snippet tools()}
	<Button variant="ghost" size="icon" href={site.repo} target="_blank" rel="noreferrer" class="size-8 text-subtle hover:text-strong" aria-label="mielwm on GitHub">
		<Icon icon={GithubIcon} size={16} />
	</Button>
	<ThemeToggle />
{/snippet}

{#snippet download()}
	<Button href={site.download} size="sm" class="w-full">
		<Icon icon={DownloadIcon} size={14} />
		Download mielwm
	</Button>
{/snippet}

<!-- no header and no hairlines: the sidebar carries the logo, search and tools, like an app's source list -->
<div class="flex flex-1 flex-col lg:flex-row">
	<!-- wide: a sticky full-height sidebar. narrow: a slim row that unfolds the same list -->
	<aside class="lg:w-[17rem] lg:shrink-0">
		<div class="sticky top-0 hidden h-dvh flex-col gap-4 py-5 lg:flex">
			<div class="flex items-center gap-1 ps-4 pe-3">
				{@render home()}
				{@render tools()}
			</div>
			<div class="px-4">
				<button
					type="button"
					onclick={() => (search.open = true)}
					class="press flex h-9 w-full items-center gap-2.5 rounded-[10px] border border-border bg-plate ps-3 pe-1.5 text-sm text-default hover:text-strong focus-visible:shadow-[var(--focus-ring)] focus-visible:outline-none"
				>
					<Icon icon={SearchIcon} size={14} />
					<span class="me-auto">Search the docs</span>
					<kbd class="key text-xs">⌘K</kbd>
				</button>
			</div>
			<nav aria-label="Docs" class="min-h-0 flex-1 overflow-y-auto px-4 pt-1 [scrollbar-width:thin]">
				{@render nav()}
			</nav>
			<div class="px-4">{@render download()}</div>
		</div>
		<div class="lg:hidden">
			<div class="flex h-14 items-center gap-1 px-4 sm:px-6">
				{@render home()}
				<Button variant="ghost" size="icon" class="size-8 text-subtle hover:text-strong" aria-label="Search the docs" onclick={() => (search.open = true)}>
					<Icon icon={SearchIcon} size={15} />
				</Button>
				<button
					type="button"
					aria-expanded={menuOpen}
					aria-controls="docs-menu"
					onclick={() => (menuOpen = !menuOpen)}
					class="press flex h-8 max-w-[11rem] items-center gap-1.5 rounded-[9px] px-2.5 text-sm text-strong hover:bg-[color-mix(in_oklab,var(--color-strong)_5%,transparent)]"
				>
					<span class="truncate">{current?.title ?? 'Overview'}</span>
					<Icon icon={ChevronDownIcon} size={15} class="text-subtle transition-transform duration-200 {menuOpen ? 'rotate-180' : ''}" />
				</button>
			</div>
			<div id="docs-menu" class="px-3 pb-4 sm:px-5" hidden={!menuOpen}>
				<nav aria-label="Docs">{@render nav()}</nav>
				<div class="flex items-center gap-1 px-1">
					<div class="me-2 flex-1">{@render download()}</div>
					{@render tools()}
				</div>
			</div>
		</div>
	</aside>
	<div class="min-w-0 flex-1">
		{@render children()}
	</div>
</div>
