<script lang="ts">
	import { afterNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import Icon from '@/components/Icon.svelte';
	import { ChevronDownIcon, SearchIcon } from '@/icons';
	import { search } from '@/search.svelte';

	let { data, children } = $props();

	const path = $derived(page.url.pathname);
	const current = $derived(data.groups.flatMap((group) => group.pages).find((p) => path === `/docs/${p.slug}`));

	// on narrow screens the page list folds away behind a button and folds again after a link
	let menuOpen = $state(false);
	afterNavigate(() => (menuOpen = false));
</script>

{#snippet nav()}
	<button
		type="button"
		onclick={() => (search.open = true)}
		class="press mb-5 flex h-9 w-full items-center gap-2.5 rounded-[10px] border border-border bg-page/60 px-3 text-sm text-subtle hover:text-strong focus-visible:shadow-[var(--focus-ring)] focus-visible:outline-none"
	>
		<Icon icon={SearchIcon} size={13} />
		Search
		<kbd class="key ms-auto text-xs">⌘K</kbd>
	</button>
	<a href="/docs" aria-current={path === '/docs' ? 'page' : undefined} class="nav-item press-soft mb-4 h-8 px-2.5 text-sm">Overview</a>
	{#each data.groups as group (group.title)}
		<section class="mb-5" aria-labelledby="nav-{group.title}">
			<h2 id="nav-{group.title}" class="mb-1 px-2.5 text-xs font-normal text-subtle">{group.title}</h2>
			<ul class="flex flex-col gap-px">
				{#each group.pages as item (item.slug)}
					<li>
						<a href="/docs/{item.slug}" aria-current={path === `/docs/${item.slug}` ? 'page' : undefined} class="nav-item press-soft h-8 px-2.5 text-sm">
							{item.title}
						</a>
					</li>
				{/each}
			</ul>
		</section>
	{/each}
{/snippet}

<div class="flex flex-1 flex-col lg:flex-row">
	<!-- wide: a sticky sidebar. narrow: a bar that unfolds the same list -->
	<aside class="border-b border-border lg:w-64 lg:shrink-0 lg:border-e lg:border-b-0">
		<nav aria-label="Docs" class="sticky top-0 hidden max-h-dvh overflow-y-auto px-4 py-6 [scrollbar-width:thin] lg:block">
			{@render nav()}
		</nav>
		<div class="lg:hidden">
			<button
				type="button"
				aria-expanded={menuOpen}
				aria-controls="docs-menu"
				onclick={() => (menuOpen = !menuOpen)}
				class="flex h-12 w-full items-center gap-2 px-4 text-sm text-strong sm:px-6"
			>
				<span class="text-subtle">Docs</span>
				<span class="text-subtle" aria-hidden="true">/</span>
				<span class="truncate">{current?.title ?? 'Overview'}</span>
				<Icon icon={ChevronDownIcon} size={15} class="ms-auto text-subtle transition-transform duration-200 {menuOpen ? 'rotate-180' : ''}" />
			</button>
			<nav id="docs-menu" aria-label="Docs" class="px-3 pb-4 sm:px-5" hidden={!menuOpen}>
				{@render nav()}
			</nav>
		</div>
	</aside>
	<div class="min-w-0 flex-1">
		{@render children()}
	</div>
</div>
