<script lang="ts">
	import * as Command from '@mielui/svelte/components/command';
	import Kbd from '@mielui/svelte/components/kbd';
	import { afterNavigate } from '$app/navigation';
	import Icon from '@/components/Icon.svelte';
	import { BookIcon, HashIcon } from '@/icons';
	import { search } from '@/search.svelte';
	import type { SearchEntry as Entry } from '@/server/docs';

	let entries = $state<Entry[]>([]);
	let failed = $state(false);
	let query = $state('');

	// the index is a prerendered file; it loads the first time the search opens
	let loading: Promise<void> | undefined;
	$effect(() => {
		if (!search.open) {
			query = '';
			return;
		}
		loading ??= fetch('/docs/search.json')
			.then((response) => (response.ok ? response.json() : Promise.reject()))
			.then((data: Entry[]) => void (entries = data))
			.catch(() => {
				failed = true;
				loading = undefined;
			});
	});

	afterNavigate(() => (search.open = false));

	const pages = $derived(entries.filter((entry) => !entry.heading));
	const fold = (text: string) => text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
	// accents and case folded once when the index arrives, not on every key
	const folded = $derived(
		entries.map((entry) => {
			const title = fold(entry.heading || entry.page);
			const body = fold(entry.text);
			return { entry, title, body, all: `${fold(entry.page)} ${title} ${body}` };
		})
	);

	// Every word has to appear somewhere in the section. Titles beat headings, headings beat body text.
	const hits = $derived.by(() => {
		const words = fold(query).split(/\s+/).filter(Boolean);
		if (!words.length) return [];
		const scored: { entry: Entry; score: number; at: number }[] = [];
		for (const { entry, title, body, all } of folded) {
			if (!words.every((word) => all.includes(word))) continue;
			const inTitle = words.filter((word) => title.includes(word)).length;
			scored.push({ entry, score: inTitle * 10 + (entry.heading ? 0 : 5) + (title.startsWith(words[0]) ? 8 : 0), at: body.indexOf(words[0]) });
		}
		return scored.sort((a, b) => b.score - a.score).slice(0, 14);
	});

	// a short piece of the section text around the first matched word
	function snippet(text: string, at: number) {
		if (at < 0) return text.slice(0, 90);
		const start = Math.max(0, text.lastIndexOf(' ', Math.max(0, at - 30)) + 1);
		return (start > 0 ? '…' : '') + text.slice(start, start + 96).trim() + (start + 96 < text.length ? '…' : '');
	}

	function onKey(event: KeyboardEvent) {
		if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
			event.preventDefault();
			search.open = !search.open;
		} else if (event.key === '/' && !search.open && !(event.target instanceof HTMLElement && event.target.closest('input, textarea, [contenteditable]'))) {
			event.preventDefault();
			search.open = true;
		}
	}
</script>

<svelte:window onkeydown={onKey} />

<Command.Root bind:open={search.open} labels={{ palette: 'Search the docs', empty: failed ? 'The search index did not load. Check your connection and try again.' : 'Nothing matches. Try fewer words.' }}>
	<Command.Content class="max-w-[36rem]">
		<Command.Search
			placeholder="Search the docs"
			aria-label="Search the docs"
			oninput={(event) => (query = event.currentTarget.value)}
		/>
		<Command.Results class="px-2 py-2">
			{#if !query}
				<Command.Group heading="Pages">
					{#each pages as entry (entry.href)}
						<Command.Item name={entry.page} href={entry.href}>
							<Icon icon={BookIcon} size={15} class="text-foreground-muted" />
							<span class="min-w-0 flex-1 truncate">{entry.page}</span>
						</Command.Item>
					{/each}
				</Command.Group>
			{:else}
				<Command.Group heading="Results">
					<!-- The ranking above is the search. Each item's name is the query itself, so the palette's
					     own filter keeps every hit, and the list stays unkeyed so arrow keys follow screen order. -->
					{#each hits as { entry, at }}
						<Command.Item name={query} href={entry.href} class="h-auto items-start py-2">
							<Icon icon={entry.heading ? HashIcon : BookIcon} size={15} class="mt-0.5 text-foreground-muted" />
							<span class="flex min-w-0 flex-1 flex-col gap-0.5 text-start">
								<span class="flex items-baseline gap-2">
									<span class="truncate text-foreground">{entry.heading || entry.page}</span>
									{#if entry.heading}<span class="shrink-0 text-xs text-foreground-muted">{entry.page}</span>{/if}
								</span>
								{#if entry.text}<span class="line-clamp-1 text-xs text-foreground-muted">{snippet(entry.text, at)}</span>{/if}
							</span>
						</Command.Item>
					{/each}
				</Command.Group>
			{/if}
		</Command.Results>
		<Command.Header class="flex items-center gap-4 border-t border-border px-4 py-2.5 text-xs text-foreground-muted">
			<span class="flex items-center gap-1.5"><Kbd shortcut="up" /><Kbd shortcut="down" />Move</span>
			<span class="flex items-center gap-1.5"><Kbd shortcut="enter" />Open</span>
			<span class="ms-auto flex items-center gap-1.5"><Kbd shortcut="esc" />Close</span>
		</Command.Header>
	</Command.Content>
</Command.Root>
