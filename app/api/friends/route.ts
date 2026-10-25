import { apiRoute, json, readJsonObject, requireService, requireUserClient } from '../../../src/server/api';
import { friendsAction, friendsActionResponse, friendsRPC, friendsSnapshot, withSharedPassports } from '../../../src/server/friends';
import { wakeFriendshipWorker } from '../../../src/server/background';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

export const GET = apiRoute(async (context) => json(
  (await withSharedPassports(requireService(context), friendsSnapshot(await friendsRPC(requireUserClient(context))))).snapshot,
), { serviceRequired: true });

export const POST = apiRoute(async (context) => {
  const action = friendsAction(await readJsonObject(context.request));
  const result = friendsActionResponse(await friendsRPC(requireUserClient(context), action), action.action);
  if (action.action === 'accept_invite') wakeFriendshipWorker();
  return json(result.snapshot ? { ...result, ...await withSharedPassports(requireService(context), result.snapshot, result.acceptedFriend) } : result);
}, { serviceRequired: true });
