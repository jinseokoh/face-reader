import {
  DateField,
  DeleteButton,
  List,
  ShowButton,
  useTable,
} from "@refinedev/antd";
import { useList, useMany } from "@refinedev/core";
import { Avatar, Space, Table, Tag, Typography } from "antd";
import { UserLink } from "../../components/user-link";
import type { AppUser, Team, TeamMember } from "../../types";

const { Text } = Typography;

function statusTag(t: Team) {
  if (!t.closed_at) return <Tag color="green">모집 중</Tag>;
  if (t.matrix_payload) return <Tag color="blue">결과표 완성</Tag>;
  return <Tag>종료</Tag>;
}

export const TeamList = () => {
  const { tableProps, result } = useTable<Team>({
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
  });

  const teams = result?.data ?? [];
  const ownerIds = teams
    .map((t) => t.owner_id)
    .filter((v): v is string => Boolean(v));

  const {
    result: { data: usersResult },
  } = useMany<AppUser>({
    resource: "users",
    ids: Array.from(new Set(ownerIds)),
    queryOptions: { enabled: ownerIds.length > 0 },
  });
  const userById = new Map<string, AppUser>(
    (usersResult ?? []).map((u) => [u.id, u]),
  );

  // 페이지에 보이는 그룹들의 멤버를 한 번에 — 등록 현황(M/N) 계산용.
  const teamIds = teams.map((t) => t.id);
  const { result: membersResult } = useList<TeamMember>({
    resource: "team_members",
    filters: [{ field: "team_id", operator: "in", value: teamIds }],
    pagination: { mode: "off" },
    queryOptions: { enabled: teamIds.length > 0 },
  });
  const counts = new Map<string, { joined: number; total: number }>();
  for (const m of membersResult?.data ?? []) {
    const c = counts.get(m.team_id) ?? { joined: 0, total: 0 };
    c.total += 1;
    if (m.metrics_id != null) c.joined += 1;
    counts.set(m.team_id, c);
  }

  return (
    <List title="케미 리스트">
      <Table {...tableProps} rowKey="id" size="middle" scroll={{ x: 1100 }}>
        <Table.Column<Team>
          title="그룹명"
          dataIndex="title"
          render={(v: string) => <Text strong>{v}</Text>}
        />
        <Table.Column<Team>
          title="방장"
          dataIndex="owner_id"
          render={(uid: string | null) => {
            if (!uid) return <Text type="secondary">(탈퇴)</Text>;
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
                <UserLink id={uid}>
                  <Text strong>{u.nickname ?? "(없음)"}</Text>
                </UserLink>
              </Space>
            );
          }}
        />
        <Table.Column<Team>
          title="등록"
          dataIndex="id"
          render={(id: string) => {
            const c = counts.get(id);
            if (!c) return <Text type="secondary">-</Text>;
            return (
              <Tag color={c.joined >= c.total ? "blue" : "default"}>
                {c.joined}/{c.total}
              </Tag>
            );
          }}
        />
        <Table.Column<Team>
          title="상태"
          dataIndex="closed_at"
          render={(_: unknown, t: Team) => statusTag(t)}
        />
        <Table.Column<Team>
          title="웹 링크"
          dataIndex="id"
          render={(id: string) => (
            <Text
              code
              copyable={{ text: `https://facely.kr/g/${id}` }}
              style={{ fontSize: 11 }}
            >
              /g/{id.slice(0, 8)}…
            </Text>
          )}
        />
        <Table.Column<Team>
          title="생성"
          dataIndex="created_at"
          sorter
          defaultSortOrder="descend"
          render={(v: string) => <DateField value={v} format="YYYY-MM-DD HH:mm" />}
        />
        <Table.Column<Team>
          title="마감"
          dataIndex="closed_at"
          sorter
          render={(v: string | null) =>
            v ? (
              <DateField value={v} format="YYYY-MM-DD HH:mm" />
            ) : (
              <Text type="secondary">-</Text>
            )
          }
        />
        <Table.Column<Team>
          title="메뉴"
          dataIndex="id"
          fixed="right"
          render={(id: string, t: Team) => (
            <Space size={4}>
              <ShowButton hideText size="small" recordItemId={id} />
              <DeleteButton
                hideText
                size="small"
                recordItemId={id}
                confirmTitle={`'${t.title}' 그룹을 삭제합니다. 멤버 명단도 함께 삭제되며 되돌릴 수 없습니다.`}
                confirmOkText="Yes"
                confirmCancelText="No"
              />
            </Space>
          )}
        />
      </Table>
    </List>
  );
};
