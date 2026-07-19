import { DateField, List, useTable } from "@refinedev/antd";
import { useMany } from "@refinedev/core";
import { Avatar, Space, Table, Tag, Tooltip, Typography } from "antd";
import { UserLink } from "../../components/user-link";
import type { AppUser, TeamReport } from "../../types";

const { Text } = Typography;

/** 채팅 신고 접수 리스트 — 스토어 UGC 정책 대응의 운영 열람 지점.
 *  reason 이 "[메시지]" 로 시작하면 개별 메시지 신고(본문 동봉), 아니면
 *  사용자 단위 신고. 방이 30일 purge 로 사라져도 행은 남는다(FK 없음). */
export const ReportList = () => {
  const { tableProps, result } = useTable<TeamReport>({
    resource: "team_reports",
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
  });

  const userIds = (result?.data ?? [])
    .flatMap((r) => [r.reporter_id, r.reported_id])
    .filter((v): v is string => !!v);

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

  const userCell = (uid: string) => {
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
  };

  return (
    <List title="신고 접수">
      <Table {...tableProps} rowKey="id" size="middle" scroll={{ x: 1100 }}>
        <Table.Column<TeamReport>
          title="신고자"
          dataIndex="reporter_id"
          render={userCell}
        />
        <Table.Column<TeamReport>
          title="피신고자"
          dataIndex="reported_id"
          render={userCell}
        />
        <Table.Column<TeamReport>
          title="유형"
          dataIndex="reason"
          width={90}
          render={(reason: string) =>
            reason.startsWith("[메시지]") ? (
              <Tag color="volcano">메시지</Tag>
            ) : (
              <Tag color="geekblue">사용자</Tag>
            )
          }
        />
        <Table.Column<TeamReport>
          title="사유 (메시지 신고는 본문 동봉)"
          dataIndex="reason"
          render={(reason: string) => (
            <Text style={{ whiteSpace: "pre-wrap" }}>
              {reason.replace(/^\[메시지\] /, "")}
            </Text>
          )}
        />
        <Table.Column<TeamReport>
          title="방"
          dataIndex="team_id"
          render={(v: string) => (
            <Tooltip title={v}>
              <Text code style={{ fontSize: 11 }}>
                {v.slice(0, 8)}…
              </Text>
            </Tooltip>
          )}
        />
        <Table.Column<TeamReport>
          title="시각"
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
