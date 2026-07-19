import { DateField, Show } from "@refinedev/antd";
import { useList, useMany, useOne } from "@refinedev/core";
import {
  Alert,
  Avatar,
  Descriptions,
  Space,
  Table,
  Tag,
  Typography,
} from "antd";
import { useParams } from "react-router";
import { UserLink } from "../../components/user-link";
import type { AppUser, TeamMessage, TeamReport } from "../../types";

const { Text } = Typography;

/** 신고 상세 — 신고 정보 + 해당 방의 전체 대화. 신고된 메시지(사유에 동봉된
 *  본문과 일치)는 하이라이트. 방이 30일 purge 됐으면 대화는 비어 있을 수 있다. */
export const ReportShow = () => {
  const { id } = useParams<{ id: string }>();

  const { result: report, query: reportQuery } = useOne<TeamReport>({
    resource: "team_reports",
    id: id ?? "",
    queryOptions: { enabled: Boolean(id) },
  });

  const { result: messagesResult } = useList<TeamMessage>({
    resource: "team_messages",
    filters: [
      { field: "team_id", operator: "eq", value: report?.team_id ?? "" },
    ],
    sorters: [{ field: "created_at", order: "asc" }],
    pagination: { pageSize: 500 },
    queryOptions: { enabled: Boolean(report?.team_id) },
  });
  const messages = messagesResult?.data ?? [];

  const userIds = [
    report?.reporter_id,
    report?.reported_id,
    ...messages.map((m) => m.sender_id),
  ].filter((v): v is string => !!v);

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

  const userCell = (uid?: string) => {
    if (!uid) return <Text type="secondary">-</Text>;
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

  const isMessageReport = report?.reason.startsWith("[메시지]") ?? false;
  // 사유 꼬리의 따옴표 본문 = 신고된 메시지 (클립됐을 수 있어 startsWith 매칭).
  const reportedSnippet = isMessageReport
    ? (report?.reason.match(/"([\s\S]*)"$/)?.[1] ?? null)
    : null;
  const isReportedMessage = (m: TeamMessage) =>
    reportedSnippet != null &&
    m.sender_id === report?.reported_id &&
    (m.body === reportedSnippet || m.body.startsWith(reportedSnippet));

  return (
    <Show isLoading={reportQuery.isLoading} title="신고 상세">
      <Space direction="vertical" size="large" style={{ width: "100%" }}>
        <Descriptions column={2} bordered size="small">
          <Descriptions.Item label="신고자">
            {userCell(report?.reporter_id)}
          </Descriptions.Item>
          <Descriptions.Item label="피신고자">
            {userCell(report?.reported_id)}
          </Descriptions.Item>
          <Descriptions.Item label="유형">
            {isMessageReport ? (
              <Tag color="volcano">메시지</Tag>
            ) : (
              <Tag color="geekblue">사용자</Tag>
            )}
          </Descriptions.Item>
          <Descriptions.Item label="접수 시각">
            {report && (
              <DateField value={report.created_at} format="YYYY-MM-DD HH:mm" />
            )}
          </Descriptions.Item>
          <Descriptions.Item label="사유" span={2}>
            <Text style={{ whiteSpace: "pre-wrap" }}>
              {report?.reason.replace(/^\[메시지\] /, "")}
            </Text>
          </Descriptions.Item>
          <Descriptions.Item label="방" span={2}>
            <Text code copyable={{ text: report?.team_id }} style={{ fontSize: 12 }}>
              {report?.team_id}
            </Text>
          </Descriptions.Item>
        </Descriptions>

        {messages.length === 0 ? (
          <Alert
            type="info"
            showIcon
            message="대화 없음"
            description="이 방의 메시지가 없습니다 — 30일 수명주기로 정리됐을 수 있습니다."
          />
        ) : (
          <Table<TeamMessage>
            dataSource={messages}
            rowKey="id"
            size="small"
            pagination={false}
            title={() => (
              <Text strong>
                방 대화 전체 ({messages.length}건) — 신고된 메시지는 강조 표시
              </Text>
            )}
            onRow={(m) =>
              isReportedMessage(m)
                ? { style: { background: "#fff1f0" } }
                : {}
            }
          >
            <Table.Column<TeamMessage>
              title="보낸이"
              dataIndex="sender_id"
              width={180}
              render={(uid: string) => (
                <Space>
                  {userCell(uid)}
                  {uid === report?.reported_id && (
                    <Tag color="volcano">피신고자</Tag>
                  )}
                </Space>
              )}
            />
            <Table.Column<TeamMessage>
              title="메시지"
              dataIndex="body"
              render={(body: string, m) => (
                <Text
                  strong={isReportedMessage(m)}
                  style={{ whiteSpace: "pre-wrap" }}
                >
                  {body}
                </Text>
              )}
            />
            <Table.Column<TeamMessage>
              title="시각"
              dataIndex="created_at"
              width={150}
              render={(v: string) => (
                <DateField value={v} format="MM-DD HH:mm:ss" />
              )}
            />
          </Table>
        )}
      </Space>
    </Show>
  );
};
