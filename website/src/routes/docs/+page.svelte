<script lang="ts">
	import Icon from '@/components/Icon.svelte';
	import Sticker from '@/components/Sticker.svelte';
	import { groupLook, pageIcon } from '@/docs-look';
	import { BookIcon, ChevronRightIcon, SearchIcon } from '@/icons';
	import { mesh } from '@/mesh';
	import { search } from '@/search.svelte';
	import { site } from '@/site';

	let { data } = $props();

	const pages = $derived(data.groups.flatMap((group) => group.pages));
	// the first stops for someone new, when the index has them
	const quick = $derived(['getting-started', 'keyboard', 'configuration'].map((slug) => pages.find((p) => p.slug === slug)).filter((p) => p !== undefined));
</script>

<svelte:head>
	<title>Docs · mielwm</title>
	<meta name="description" content="How to install mielwm, use its workspaces and overview, and set it up the way you like." />
	<meta property="og:title" content="Docs · mielwm" />
</svelte:head>

<div class="mx-auto w-full max-w-[60rem] px-4 py-8 sm:px-8 sm:py-12">
	<!-- the same title panel as every docs page, in the landing page's lavender -->
	<header class="stagger group/section relative isolate mb-14 flex flex-col items-start gap-3 pt-2" style:--tint="#b8b4ff">
		<div class="mesh-glow pointer-events-none absolute -inset-x-4 -top-8 -bottom-6 -z-10 sm:-inset-x-8" aria-hidden="true" data-rise></div>
		<p class="flex items-center gap-2 text-sm font-medium text-strong">
			<Sticker icon={BookIcon} bg={mesh.violet} />
			mielwm docs
		</p>
		<h1 class="display text-4xl">Documentation</h1>
		<p class="max-w-[38rem] text-xl leading-normal text-default">How to install mielwm, find your way around the canvas, and set it up the way you like.</p>
		<button
			type="button"
			onclick={() => (search.open = true)}
			class="press-soft mt-4 flex h-11 w-full max-w-[32rem] items-center gap-2.5 rounded-[12px] border border-border bg-plate ps-3.5 pe-2 text-base text-default shadow-[0_1px_2px_rgb(0_0_0/0.04)] hover:border-border-strong hover:text-strong focus-visible:shadow-[var(--focus-ring)] focus-visible:outline-none"
		>
			<Icon icon={SearchIcon} size={15} />
			<span class="me-auto">Search the docs</span>
			<kbd class="key text-xs">⌘K</kbd>
		</button>
		{#if quick.length}
			<nav aria-label="Start here" class="flex flex-wrap gap-2">
				{#each quick as item (item.slug)}
					<a href="/docs/{item.slug}" class="press flex h-8 items-center gap-2 rounded-full border border-border bg-plate px-3 text-sm text-strong hover:border-border-strong hover:bg-selected">
						<Icon icon={pageIcon(item.slug)} size={13} class="text-subtle" />
						{item.title}
					</a>
				{/each}
			</nav>
		{/if}
	</header>

	{#if data.groups.length}
		<div class="flex flex-col gap-12">
			{#each data.groups as group (group.title)}
				{@const look = groupLook(group.title)}
				<section aria-labelledby="group-{group.title}" class="group/section flex flex-col gap-4">
					<h2 id="group-{group.title}" class="flex items-center gap-2.5 text-lg">
						<Sticker icon={look.icon} bg={look.mesh} />
						{group.title}
					</h2>
					<ul class="grid gap-3 sm:grid-cols-2">
						{#each group.pages as item (item.slug)}
							<li class="flex">
								<a href="/docs/{item.slug}" class="tile group press-soft flex w-full items-start gap-4 p-5 hover:shadow-[0_0_0_1px_var(--color-border-strong),0_6px_20px_-10px_rgb(0_0_0/0.2)]">
									<span class="grain grid size-9 shrink-0 place-items-center rounded-[10px] text-white" style:background={look.mesh} aria-hidden="true">
										<Icon icon={pageIcon(item.slug)} size={16} />
									</span>
									<span class="flex min-w-0 flex-1 flex-col gap-1">
										<span class="text-base text-strong">{item.title}</span>
										{#if item.lead}<span class="text-sm leading-relaxed text-subtle">{item.lead}</span>{/if}
									</span>
									<Icon icon={ChevronRightIcon} size={14} class="mt-1 shrink-0 text-subtle transition-transform duration-150 group-hover:translate-x-0.5 group-hover:text-strong motion-reduce:transition-none" />
								</a>
							</li>
						{/each}
					</ul>
				</section>
			{/each}
		</div>
	{:else}
		<p class="text-base">The docs are on their way. Until then, the <a class="link" href={site.repo} target="_blank" rel="noreferrer">README on GitHub</a> covers everything.</p>
	{/if}
</div>
