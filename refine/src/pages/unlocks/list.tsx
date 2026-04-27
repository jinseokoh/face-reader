import { DateField, List, ShowButton, useTable } from "@refinedev/antd";
import { useMany } from "@refinedev/core";
import { Avatar, Space, Table, Tag, Tooltip, Typography } from "antd";
import type { AppUser, Unlock } from "../../types";

const { Text } = Typography;

function scoreColor(s: number): string {
  if (s >= 90) return "magenta"; // 천작지합
  if (s >= 78) return "geekblue"; // 상경여빈
  if (s >= 56) return "green"; // 마합가성
  return "default"; // 형극난조
}

function scoreLabel(s: number): string {
  if (s >= 90) return "천작지합";
  if (s >= 78) return "상경여빈";
  if (s >= 56) return "마합가성";
  return "형극난조";
}

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
      <Table
        {...tableProps}
        rowKey={(r) => `${r.user_id}::${r.pair_key}`}
        size="middle"
        scroll={{ x: 1100 }}
      >
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
          title="점수"
          dataIndex="total_score"
          sorter
          render={(v: number | null) => {
            if (v == null) return <Text type="secondary">-</Text>;
            const s = Number(v);
            return (
              <Tooltip title={scoreLabel(s)}>
                <Tag color={scoreColor(s)}>{s.toFixed(1)}</Tag>
              </Tooltip>
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
        <Table.Column<Unlock>
          title="해석"
          dataIndex="pair_key"
          fixed="right"
          render={(pairKey: string) => (
            <ShowButton hideText size="small" recordItemId={pairKey} />
          )}
        />
      </Table>
    </List>
  );
};
