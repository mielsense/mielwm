<script lang="ts">
	import Icon from '@/components/Icon.svelte';
	import { ChevronRightIcon } from '@/icons';
	import { site } from '@/site';

	let { data } = $props();
</script>

<svelte:head>
	<title>Docs · mielwm</title>
	<meta name="description" content="How to install mielwm, use its workspaces and overview, and set it up the way you like." />
	<meta property="og:title" content="Docs · mielwm" />
</svelte:head>

<div class="mx-auto w-full max-w-[44rem] px-4 py-8 sm:px-8 sm:py-12">
	<header class="stagger mb-12 flex flex-col gap-3">
		<h1 class="display text-4xl">Documentation</h1>
		<p class="text-xl leading-normal text-subtle">How to install mielwm, find your way around the canvas, and set it up the way you like.</p>
	</header>

	{#if data.groups.length}
		<div class="flex flex-col gap-10">
			{#each data.groups as group (group.title)}
				<section aria-labelledby="group-{group.title}" class="flex flex-col gap-3">
					<h2 id="group-{group.title}" class="text-sm font-normal text-subtle">{group.title}</h2>
					<div class="shell">
						<ul class="sheet flex flex-col">
							{#each group.pages as item (item.slug)}
								<li class="overflow-hidden border-t border-border first:rounded-t-[13px] first:border-t-0 last:rounded-b-[13px]">
									<a href="/docs/{item.slug}" class="group press-soft flex items-center gap-4 px-4 py-3.5 outline-offset-[-2px] hover:bg-selected/60">
										<span class="flex min-w-0 flex-1 flex-col gap-0.5">
											<span class="text-base text-strong">{item.title}</span>
											{#if item.lead}<span class="text-sm text-subtle">{item.lead}</span>{/if}
										</span>
										<Icon icon={ChevronRightIcon} size={14} class="shrink-0 text-subtle transition-transform duration-150 group-hover:translate-x-0.5 group-hover:text-strong motion-reduce:transition-none" />
									</a>
								</li>
							{/each}
						</ul>
					</div>
				</section>
			{/each}
		</div>
	{:else}
		<p class="text-base">The docs are on their way. Until then, the <a class="link" href={site.repo} target="_blank" rel="noreferrer">README on GitHub</a> covers everything.</p>
	{/if}
</div>
