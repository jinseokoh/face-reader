import { DateField, List, useTable } from "@refinedev/antd";
import { useMany } from "@refinedev/core";
import { Avatar, Space, Table, Typography } from "antd";
import type { AppUser, Unlock } from "../../types";

const { Text } = Typography;

export const UnlockList = () => {
  const { tableProps, result } = useTable<Unlock>({
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
  });

  const userIds = (result?.data ?? []).map((u) => u.user_id);

  const {
    result: { data: usersResult },
  } = useMany<AppUser>({
    resource: "users",
    ids: Array.from(new Set(userIds)),
    queryOptions: { enabled: userIds.length > 0 },
  });

  const userById = new Map<string, AppUser>(
    (usersResult ?? []).map((u) => [u.id, u])
  );

  return (
    <List title="궁합 unlock 내역">
      <Table {...tableProps} rowKey={(r) => `${r.user_id}::${r.pair_key}`} size="middle">
        <Table.Column<Unlock>
          title="사용자"
          dataIndex="user_id"
          render={(uid: string) => {
            const u = userById.get(uid);
            if (!u)
              return (
                <Text code style={{ fontSize: 11 }}>
                  {uid.slice(0, 8)}…
                </Text>
              );
            return (
              <Space>
                <Avatar src={u.profile_image_url ?? undefined} size={24}>
                  {u.nickname?.[0] ?? "?"}
                </Avatar>
                <Text strong>{u.nickname ?? "(없음)"}</Text>
              </Space>
            );
          }}
        />
        <Table.Column<Unlock>
          title="pair_key (my::album)"
          dataIndex="pair_key"
          render={(v: string) => (
            <Text code copyable={{ text: v }} style={{ fontSize: 11 }}>
              {v}
            </Text>
          )}
        />
        <Table.Column<Unlock>
          title="해제 시각"
          dataIndex="created_at"
          sorter
          defaultSortOrder="descend"
          render={(v: string) => (
            <DateField value={v} format="YYYY-MM-DD HH:mm" />
          )}
        />
      </Table>
    </List>
  );
};
