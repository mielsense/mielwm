<script lang="ts">
	import { afterNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import { Button } from '@mielui/svelte/components/button';
	import Icon from '@/components/Icon.svelte';
	import Sticker from '@/components/Sticker.svelte';
	import ThemeToggle from '@/components/ThemeToggle.svelte';
	import { groupLook, pageIcon } from '@/docs-look';
	import { ChevronDownIcon, DownloadIcon, GithubIcon, SearchIcon } from '@/icons';
	import { search } from '@/search.svelte';
	import { docHref, site } from '@/site';

	let { data, children } = $props();

	const path = $derived(page.url.pathname);
	const current = $derived([...data.nav.top, ...data.nav.groups.flatMap((group) => group.pages)].find((p) => path === docHref(p.slug)));
	const here = (slug: string) => (path === docHref(slug) ? 'page' : undefined);

	// on narrow screens the page list folds away behind a button and folds again after a link
	let menuOpen = $state(false);
	afterNavigate(() => (menuOpen = false));
</script>

{#snippet nav()}
	<!-- like ui.miel.my: the index's loose links first, then each group under its sticker with its pages indented -->
	{#if data.nav.top.length}
		<ul class="mb-5 flex flex-col gap-px">
			{#each data.nav.top as item (item.slug)}
				<li>
					<a href={docHref(item.slug)} aria-current={here(item.slug)} class="nav-item press-soft h-8 gap-2.5 px-2.5 text-sm">
						<Icon icon={pageIcon(item.slug)} size={14} class="opacity-70" />
						{item.title}
					</a>
				</li>
			{/each}
		</ul>
	{/if}
	{#each data.nav.groups as group (group.title)}
		{@const look = groupLook(group.title)}
		<section class="group/section mb-5" aria-labelledby="nav-{group.title}">
			<h2 id="nav-{group.title}" class="mb-1 flex h-8 items-center gap-2.5 px-2 text-sm font-medium text-strong">
				<Sticker icon={look.icon} bg={look.mesh} size={20} />
				{group.title}
			</h2>
			<ul class="flex flex-col gap-px">
				{#each group.pages as item (item.slug)}
					<li>
						<a href={docHref(item.slug)} aria-current={here(item.slug)} class="nav-item press-soft h-8 ps-9 pe-2.5 text-sm">
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
	<Button href="/download" size="sm" class="w-full">
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
					<span class="truncate">{current?.title ?? 'Docs'}</span>
					<Icon icon={ChevronDownIcon} size={15} class="text-subtle transition-transform duration-200 {menuOpen ? 'rotate-180' : ''}" />
				</button>
			</div>
			<!-- Grows from zero height so it slides down and pushes the page; inert keeps it out of the tab order while closed. -->
			<div
				id="docs-menu"
				inert={!menuOpen}
				class="grid transition-[grid-template-rows] duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none {menuOpen ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}"
			>
				<div class="min-h-0 overflow-hidden">
					<div
						class="px-3 pb-4 transition-[opacity,translate] duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none sm:px-5 {menuOpen ? 'translate-y-0 opacity-100' : '-translate-y-2 opacity-0'}"
					>
						<nav aria-label="Docs">{@render nav()}</nav>
						<div class="flex items-center gap-1 px-1">
							<div class="me-2 flex-1">{@render download()}</div>
							{@render tools()}
						</div>
					</div>
				</div>
			</div>
		</div>
	</aside>
	<div class="min-w-0 flex-1">
		{@render children()}
	</div>
</div>
