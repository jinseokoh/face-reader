import { CloseOutlined } from "@ant-design/icons";
import { DateField, Show } from "@refinedev/antd";
import { useInvalidate, useList, useMany } from "@refinedev/core";
import {
  Alert,
  App,
  Avatar,
  Button,
  Descriptions,
  Popconfirm,
  Space,
  Table,
  Tag,
  Typography,
} from "antd";
import { AwsClient } from "aws4fetch";
import { useParams } from "react-router";
import { Link } from "react-router";
import { adminClient } from "../../providers/data";
import type { MetricEntry, Team, TeamMember } from "../../types";
import { metricThumbUrl } from "../../types";

const { Text, Title } = Typography;

// 브라우저 직접 R2 조작 — refine 는 로컬 전용 admin (ad-videos/create 와 동일 패턴).
const R2_ENV = (import.meta as { env: Record<string, string> }).env;
const R2 = {
  accountId: R2_ENV.VITE_R2_ACCOUNT_ID,
  bucket: R2_ENV.VITE_R2_BUCKET_NAME || "facely",
  accessKeyId: R2_ENV.VITE_R2_ACCESS_KEY_ID,
  secretAccessKey: R2_ENV.VITE_R2_SECRET_ACCESS_KEY,
};

/** R2 객체 삭제 — 404 도 성공 취급. 자격 미설정이면 false. */
async function deleteR2Object(key: string): Promise<boolean> {
  if (!R2.accountId || !R2.accessKeyId || !R2.secretAccessKey) return false;
  const client = new AwsClient({
    accessKeyId: R2.accessKeyId,
    secretAccessKey: R2.secretAccessKey,
    service: "s3",
    region: "auto",
  });
  const url = `https://${R2.accountId}.r2.cloudflarestorage.com/${R2.bucket}/${key}`;
  const signed = await client.sign(new Request(url, { method: "DELETE" }), {
    aws: { signQuery: true },
  });
  const res = await fetch(signed.url, { method: "DELETE" });
  return res.ok || res.status === 404;
}

export const TeamShow = () => {
  const { id } = useParams<{ id: string }>();
  const { message } = App.useApp();
  const invalidate = useInvalidate();

  /** 등록 삭제 — R2 썸네일 + metrics row. FK(on delete set null)가
   *  team_members.metrics_id 를 비워 슬롯이 '대기'로 되돌아간다. */
  const handleUnregister = async (metricsId: string, body?: string) => {
    try {
      const key = body
        ? (JSON.parse(body) as { thumbnailKey?: string }).thumbnailKey
        : undefined;
      if (key) {
        const ok = await deleteR2Object(key);
        if (!ok) message.warning("R2 썸네일 삭제 실패 — row 는 계속 삭제합니다");
      }
      const { error } = await adminClient
        .from("metrics")
        .delete()
        .eq("id", metricsId);
      if (error) {
        message.error(`metrics 삭제 실패: ${error.message}`);
        return;
      }
      message.success("등록 삭제됨 (슬롯은 대기로 전환)");
      invalidate({ resource: "team_members", invalidates: ["list"] });
      invalidate({ resource: "metrics", invalidates: ["list", "many"] });
    } catch (e) {
      message.error(`삭제 실패: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

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
              render={(v: string | null, m) =>
                v ? (
                  <Space size={4}>
                    <Tag color="blue">등록</Tag>
                    <Popconfirm
                      title="등록 삭제"
                      description={`'${m.name}' 의 metrics row 와 R2 썸네일을 삭제합니다. 되돌릴 수 없습니다.`}
                      okText="Yes"
                      cancelText="No"
                      okButtonProps={{ danger: true }}
                      onConfirm={() =>
                        handleUnregister(v, metricById.get(v)?.body)
                      }
                    >
                      <Button
                        size="small"
                        type="text"
                        danger
                        icon={<CloseOutlined />}
                      />
                    </Popconfirm>
                  </Space>
                ) : (
                  <Tag>대기</Tag>
                )
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
