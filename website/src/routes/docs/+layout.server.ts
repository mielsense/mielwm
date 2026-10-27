import { navigation } from '@/server/docs';

export const load = () => ({ groups: navigation() });
