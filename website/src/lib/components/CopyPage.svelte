<script lang="ts">
	// Copies the page's Markdown source, the same text as docs/<page>.md, for pasting into a chat or a note.
	import { Button, type ButtonStatus } from '@mielui/svelte/components/button';
	import Icon from '@/components/Icon.svelte';
	import { CopyIcon } from '@/icons';

	let { source }: { source: string } = $props();

	let status = $state<ButtonStatus>('idle');
	let timer: ReturnType<typeof setTimeout> | undefined;

	async function copy() {
		clearTimeout(timer);
		try {
			await navigator.clipboard.writeText(source);
			status = 'success';
		} catch {
			status = 'error';
		}
		timer = setTimeout(() => (status = 'idle'), 2000);
	}

	// a new page starts idle
	$effect(() => {
		void source;
		return () => {
			clearTimeout(timer);
			status = 'idle';
		};
	});
</script>

<Button variant="secondary" size="sm" {status} labels={{ success: 'Copied', error: 'Copy failed' }} onclick={copy} class="shrink-0">
	<Icon icon={CopyIcon} size={14} />
	Copy page
</Button>
