import { DateField, Show } from "@refinedev/antd";
import { useList, useMany } from "@refinedev/core";
import {
  Alert,
  Avatar,
  Descriptions,
  Space,
  Table,
  Tag,
  Tooltip,
  Typography,
} from "antd";
import { useParams } from "react-router";
import { Link } from "react-router";
import { UserLink } from "../../components/user-link";
import type { AppUser, MetricEntry, Team, TeamMember } from "../../types";
import { metricThumbUrl } from "../../types";

const { Text, Title } = Typography;

/** result_payload band 코드(0~3) — 앱 BattleBand 와 동일 라벨·색. */
const BAND_LABEL = ["천생연분", "금슬화합", "상부상조", "형극난조"];
const BAND_COLOR = ["#2E7D32", "#1565C0", "#EF6C00", "#D32F2F"];

function statusTag(t: Team) {
  switch (t.status) {
    case "recruiting":
      return <Tag color="green">모집 중</Tag>;
    case "revealing":
      return <Tag color="blue">발표 중</Tag>;
    case "completed":
      return <Tag color="blue">완료</Tag>;
    default:
      return <Tag>인원 미달 종료</Tag>;
  }
}

function ageLabel(t: Team) {
  if (t.age_min == null || t.age_max == null) return "전연령";
  if (t.age_min === t.age_max) return `${t.age_min}대`;
  return `${t.age_min}대~${t.age_max}대`;
}

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
    sorters: [{ field: "slot_no", order: "asc" }],
    pagination: { mode: "off" },
    queryOptions: { enabled: Boolean(id) },
  });
  const members = membersResult?.data ?? [];
  const memberUserIds = Array.from(new Set(members.map((m) => m.user_id)));

  // 닉네임·프로필 — team_members.user_id → users.
  const {
    result: { data: memberUsers },
  } = useMany<AppUser>({
    resource: "users",
    ids: memberUserIds,
    queryOptions: { enabled: memberUserIds.length > 0 },
  });
  const userById = new Map<string, AppUser>(
    (memberUsers ?? []).map((u) => [u.id, u]),
  );

  // 아바타·관상 row 링크 — 각 참가자의 my-face metrics row.
  const { result: metricsResult } = useList<MetricEntry>({
    resource: "metrics",
    filters: [
      { field: "user_id", operator: "in", value: memberUserIds },
      { field: "is_my_face", operator: "eq", value: true },
    ],
    pagination: { mode: "off" },
    queryOptions: { enabled: memberUserIds.length > 0 },
  });
  const metricByUser = new Map<string, MetricEntry>(
    (metricsResult?.data ?? [])
      .filter((m): m is MetricEntry & { user_id: string } =>
        Boolean(m.user_id),
      )
      .map((m) => [m.user_id, m]),
  );

  const payload = team?.result_payload ?? null;
  const players = payload
    ? [...payload.players].sort((x, y) => x.slot - y.slot)
    : [];
  const pairBySlots = new Map(
    (payload?.pairs ?? []).map((p) => [
      `${Math.min(p.a, p.b)}-${Math.max(p.a, p.b)}`,
      p,
    ]),
  );
  const nameBySlot = new Map(players.map((p) => [p.slot, p.name]));

  return (
    <Show isLoading={teamQuery.isLoading} title="케미 그룹">
      <Space direction="vertical" size="large" style={{ width: "100%" }}>
        {team && (
          <Descriptions column={2} bordered size="small">
            <Descriptions.Item label="그룹명" span={2}>
              <Space>
                <Text strong>{team.title}</Text>
                {team.is_private ? <Tag>비밀</Tag> : <Tag color="cyan">공개</Tag>}
              </Space>
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
            <Descriptions.Item label="유형">
              {team.room_kind === "match" ? "이성 케미" : "전체 케미"}
            </Descriptions.Item>
            <Descriptions.Item label="비밀번호">
              {team.password ? (
                <Text code copyable>
                  {team.password}
                </Text>
              ) : (
                <Text type="secondary">-</Text>
              )}
            </Descriptions.Item>
            <Descriptions.Item label="정원">
              {members.length} / {team.max_players} 명
            </Descriptions.Item>
            <Descriptions.Item label="연령대">{ageLabel(team)}</Descriptions.Item>
            <Descriptions.Item label="상태">{statusTag(team)}</Descriptions.Item>
            <Descriptions.Item label="생성">
              <DateField value={team.created_at} format="YYYY-MM-DD HH:mm" />
            </Descriptions.Item>
            <Descriptions.Item label="시작 · 마감">
              {team.started_at ? (
                <DateField value={team.started_at} format="YYYY-MM-DD HH:mm" />
              ) : (
                <Text type="secondary">-</Text>
              )}
              {" · "}
              {team.closed_at ? (
                <DateField value={team.closed_at} format="YYYY-MM-DD HH:mm" />
              ) : (
                <Text type="secondary">-</Text>
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
            <Table.Column<TeamMember> title="슬롯" dataIndex="slot_no" width={56} />
            <Table.Column<TeamMember>
              title="멤버"
              dataIndex="user_id"
              render={(uid: string, m) => {
                const u = userById.get(uid);
                const thumb = metricThumbUrl(metricByUser.get(uid)?.body);
                return (
                  <Space>
                    <Avatar
                      src={thumb ?? u?.profile_image_url ?? undefined}
                      size={32}
                    >
                      {u?.nickname?.[0] ?? "?"}
                    </Avatar>
                    <UserLink id={uid}>
                      <Text strong>{u?.nickname ?? `${uid.slice(0, 8)}…`}</Text>
                    </UserLink>
                    {m.is_owner && <Tag color="gold">방장</Tag>}
                  </Space>
                );
              }}
            />
            <Table.Column<TeamMember>
              title="성별"
              dataIndex="gender"
              render={(g: string) =>
                g === "male" ? (
                  <Tag color="blue">남</Tag>
                ) : (
                  <Tag color="magenta">여</Tag>
                )
              }
            />
            <Table.Column<TeamMember>
              title="관상 row"
              dataIndex="user_id"
              render={(uid: string) => {
                const mid = metricByUser.get(uid)?.id;
                return mid ? (
                  <Link to={`/metrics/show/${mid}`}>
                    <Text code style={{ fontSize: 11 }}>
                      {mid.slice(0, 8)}…
                    </Text>
                  </Link>
                ) : (
                  <Text type="secondary">-</Text>
                );
              }}
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
            <Title level={5}>결과표 (result_payload)</Title>
            <div style={{ overflowX: "auto" }}>
              <table style={{ borderCollapse: "collapse" }}>
                <thead>
                  <tr>
                    <th />
                    {players.map((p) => (
                      <th key={p.slot} style={headCell}>
                        {p.name}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {players.map((row) => (
                    <tr key={row.slot}>
                      <th style={{ ...headCell, textAlign: "right" }}>
                        {row.name}
                      </th>
                      {players.map((col) => {
                        if (row.slot === col.slot)
                          return (
                            <td key={col.slot} style={bodyCell}>
                              ·
                            </td>
                          );
                        const a = Math.min(row.slot, col.slot);
                        const b = Math.max(row.slot, col.slot);
                        const pair = pairBySlots.get(`${a}-${b}`);
                        // 이성방 동성 쌍은 pairs 에 없다 — 빈 칸.
                        if (!pair) return <td key={col.slot} style={bodyCell} />;
                        return (
                          <td key={col.slot} style={bodyCell}>
                            <Tooltip title={BAND_LABEL[pair.band] ?? pair.band}>
                              <span
                                style={{
                                  display: "inline-block",
                                  width: 14,
                                  height: 14,
                                  borderRadius: "50%",
                                  background:
                                    BAND_COLOR[pair.band] ?? "#999",
                                }}
                              />
                            </Tooltip>
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Text type="secondary" style={{ fontSize: 12 }}>
              베스트 매칭: {nameBySlot.get(payload.best.a) ?? payload.best.a} ·{" "}
              {nameBySlot.get(payload.best.b) ?? payload.best.b} (
              {payload.best.score}점)
            </Text>
          </div>
        ) : team && team.status !== "recruiting" ? (
          <Alert
            type="warning"
            showIcon
            message="결과표 없음"
            description={
              team.status === "expired"
                ? "인원이 모이지 않아 종료된 그룹입니다 — 결과표가 만들어지지 않습니다."
                : "시작된 그룹이지만 result_payload 가 아직 없습니다 — 참가자가 결과 화면을 열면 기록됩니다."
            }
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
