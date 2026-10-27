<script lang="ts">
	import { Button } from '@mielui/svelte/components/button';
	import Icon from '@/components/Icon.svelte';
	import { MoonIcon, SunIcon } from '@/icons';
	import { theme } from '@/theme.svelte';
</script>

<!-- both glyphs are rendered and CSS picks one, so the prerendered page never shows the wrong one -->
<Button
	variant="ghost"
	size="icon"
	class="relative size-7 text-subtle hover:text-strong"
	aria-label="Switch between light and dark"
	onclick={(event) => theme.toggle({ x: event.clientX, y: event.clientY })}
>
	<Icon icon={MoonIcon} size={15} class="absolute transition-[opacity,scale] duration-200 dark:scale-50 dark:opacity-0" />
	<Icon icon={SunIcon} size={15} class="absolute scale-50 opacity-0 transition-[opacity,scale] duration-200 dark:scale-100 dark:opacity-100" />
</Button>
