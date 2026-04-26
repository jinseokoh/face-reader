import { DateField, List, useTable } from "@refinedev/antd";
import { useMany } from "@refinedev/core";
import { Avatar, Space, Table, Tag, Tooltip, Typography } from "antd";
import type { AppUser, MetricEntry } from "../../types";

const { Text } = Typography;

const SOURCE_COLOR: Record<string, string> = {
  camera: "blue",
  album: "green",
};

const GENDER_LABEL: Record<string, string> = {
  male: "남",
  female: "여",
};

export const MetricList = () => {
  const { tableProps, result } = useTable<MetricEntry>({
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
    filters: {
      mode: "server",
    },
  });

  const userIds = (result?.data ?? [])
    .map((m) => m.user_id)
    .filter((v): v is string => !!v);

  const {
    result: { data: usersResult },
    query: { isLoading: usersLoading },
  } = useMany<AppUser>({
    resource: "users",
    ids: Array.from(new Set(userIds)),
    queryOptions: { enabled: userIds.length > 0 },
  });

  const userById = new Map<string, AppUser>(
    (usersResult ?? []).map((u) => [u.id, u])
  );

  const now = Date.now();

  return (
    <List title="metric 업로드">
      <Table {...tableProps} rowKey="id" size="middle" scroll={{ x: 1100 }}>
        <Table.Column<MetricEntry>
          title="업로더"
          dataIndex="user_id"
          render={(uid: string | null) => {
            if (!uid) return <Tag color="default">anon</Tag>;
            const u = userById.get(uid);
            if (usersLoading) return <Text type="secondary">로딩…</Text>;
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
        <Table.Column<MetricEntry>
          title="source"
          dataIndex="source"
          filters={[
            { text: "camera", value: "camera" },
            { text: "album", value: "album" },
          ]}
          render={(v: string) => (
            <Tag color={SOURCE_COLOR[v] ?? "default"}>{v}</Tag>
          )}
        />
        <Table.Column<MetricEntry>
          title="성별"
          dataIndex="gender"
          filters={[
            { text: "남", value: "male" },
            { text: "여", value: "female" },
          ]}
          render={(v: string) => GENDER_LABEL[v] ?? v}
        />
        <Table.Column<MetricEntry> title="연령대" dataIndex="age_group" />
        <Table.Column<MetricEntry>
          title="ethnicity"
          dataIndex="ethnicity"
          render={(v: string) => (
            <Text style={{ fontSize: 12 }}>{v}</Text>
          )}
        />
        <Table.Column<MetricEntry>
          title="alias"
          dataIndex="alias"
          render={(v: string | null) =>
            v ? <Text>{v}</Text> : <Text type="secondary">-</Text>
          }
        />
        <Table.Column<MetricEntry>
          title="업로드"
          dataIndex="created_at"
          sorter
          defaultSortOrder="descend"
          render={(v: string) => (
            <DateField value={v} format="YYYY-MM-DD HH:mm" />
          )}
        />
        <Table.Column<MetricEntry>
          title="만료"
          dataIndex="expires_at"
          sorter
          render={(v: string) => {
            const ms = new Date(v).getTime() - now;
            const days = Math.floor(ms / 86_400_000);
            const expired = ms < 0;
            const soon = !expired && days < 3;
            return (
              <Tooltip title={v}>
                <Tag color={expired ? "red" : soon ? "orange" : "default"}>
                  {expired
                    ? "만료됨"
                    : days === 0
                    ? "오늘 만료"
                    : `${days}일 남음`}
                </Tag>
              </Tooltip>
            );
          }}
        />
        <Table.Column<MetricEntry>
          title="ID"
          dataIndex="id"
          render={(v: string) => (
            <Text code copyable={{ text: v }} style={{ fontSize: 11 }}>
              {v.slice(0, 8)}…
            </Text>
          )}
        />
      </Table>
    </List>
  );
};
