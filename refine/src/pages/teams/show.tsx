import { DateField, Show } from "@refinedev/antd";
import { useList, useMany } from "@refinedev/core";
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
import { Link } from "react-router";
import type { MetricEntry, Team, TeamMember } from "../../types";
import { metricThumbUrl } from "../../types";

const { Text, Title } = Typography;

export const TeamShow = () => {
  const { id } = useParams<{ id: string }>();

  const {
    result: { data: teamRows },
    query: teamQuery,
  } = useMany<Team>({
    resource: "teams",
    ids: id ? [id] : [],
    queryOptions: { enabled: Boolean(id) },
  });
  const team = (teamRows ?? [])[0];

  const { result: membersResult } = useList<TeamMember>({
    resource: "team_members",
    filters: [{ field: "team_id", operator: "eq", value: id }],
    sorters: [{ field: "joined_at", order: "asc" }],
    pagination: { mode: "off" },
    queryOptions: { enabled: Boolean(id) },
  });
  const members = membersResult?.data ?? [];

  const metricsIds = members
    .map((m) => m.metrics_id)
    .filter((v): v is string => Boolean(v));
  const {
    result: { data: metricsRows },
  } = useMany<MetricEntry>({
    resource: "metrics",
    ids: metricsIds,
    queryOptions: { enabled: metricsIds.length > 0 },
  });
  const metricById = new Map<string, MetricEntry>(
    (metricsRows ?? []).map((m) => [m.id, m]),
  );

  const payload = team?.matrix_payload ?? null;

  return (
    <Show isLoading={teamQuery.isLoading} title="케미 그룹">
      <Space direction="vertical" size="large" style={{ width: "100%" }}>
        {team && (
          <Descriptions column={2} bordered size="small">
            <Descriptions.Item label="그룹명" span={2}>
              <Text strong>{team.title}</Text>
            </Descriptions.Item>
            <Descriptions.Item label="웹 링크" span={2}>
              <Text
                code
                copyable={{ text: `https://facely.kr/g/${team.id}` }}
                style={{ fontSize: 12 }}
              >
                https://facely.kr/g/{team.id}
              </Text>
            </Descriptions.Item>
            <Descriptions.Item label="생성">
              <DateField value={team.created_at} format="YYYY-MM-DD HH:mm" />
            </Descriptions.Item>
            <Descriptions.Item label="마감">
              {team.closed_at ? (
                <DateField value={team.closed_at} format="YYYY-MM-DD HH:mm" />
              ) : (
                <Tag color="green">모집 중</Tag>
              )}
            </Descriptions.Item>
          </Descriptions>
        )}

        <div>
          <Title level={5}>참여 멤버 ({members.length})</Title>
          <Table
            dataSource={members}
            rowKey="id"
            size="small"
            pagination={false}
          >
            <Table.Column<TeamMember>
              title="멤버"
              dataIndex="name"
              render={(name: string, m) => {
                const metric = m.metrics_id
                  ? metricById.get(m.metrics_id)
                  : undefined;
                const thumb = metricThumbUrl(metric?.body);
                return (
                  <Space>
                    <Avatar src={thumb ?? undefined} size={32}>
                      {name[0]}
                    </Avatar>
                    <Text strong>{name}</Text>
                    {m.is_owner && <Tag color="gold">방장</Tag>}
                  </Space>
                );
              }}
            />
            <Table.Column<TeamMember>
              title="등록"
              dataIndex="metrics_id"
              render={(v: string | null) =>
                v ? <Tag color="blue">등록</Tag> : <Tag>대기</Tag>
              }
            />
            <Table.Column<TeamMember>
              title="관상 row"
              dataIndex="metrics_id"
              render={(v: string | null) =>
                v ? (
                  <Link to={`/metrics/show/${v}`}>
                    <Text code style={{ fontSize: 11 }}>
                      {v.slice(0, 8)}…
                    </Text>
                  </Link>
                ) : (
                  <Text type="secondary">-</Text>
                )
              }
            />
            <Table.Column<TeamMember>
              title="합류"
              dataIndex="joined_at"
              render={(v: string) => (
                <DateField value={v} format="YYYY-MM-DD HH:mm" />
              )}
            />
          </Table>
        </div>

        {payload ? (
          <div>
            <Title level={5}>결과표 (matrix_payload)</Title>
            <div style={{ overflowX: "auto" }}>
              <table style={{ borderCollapse: "collapse" }}>
                <thead>
                  <tr>
                    <th />
                    {payload.members.map((n, j) => (
                      <th key={j} style={headCell}>
                        {n}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {payload.members.map((n, i) => (
                    <tr key={i}>
                      <th style={{ ...headCell, textAlign: "right" }}>{n}</th>
                      {payload.members.map((_, j) => {
                        const a = Math.min(i, j);
                        const b = Math.max(i, j);
                        const pair = payload.pairs.find(
                          (p) => p.a === a && p.b === b,
                        );
                        return (
                          <td key={j} style={bodyCell} title={pair?.l}>
                            {i === j ? "·" : (pair?.e ?? "")}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ) : team?.closed_at ? (
          <Alert
            type="warning"
            showIcon
            message="결과표 없음"
            description="닫힌 그룹이지만 matrix_payload 가 없습니다 — 전원 미충족 상태로 48h cron 이 마감했을 수 있습니다."
          />
        ) : null}
      </Space>
    </Show>
  );
};

const headCell: React.CSSProperties = {
  fontSize: 12,
  fontWeight: 400,
  padding: 6,
  whiteSpace: "nowrap",
};

const bodyCell: React.CSSProperties = {
  width: 36,
  height: 36,
  textAlign: "center",
  fontSize: 16,
  border: "1px solid rgba(128,128,128,0.25)",
};
