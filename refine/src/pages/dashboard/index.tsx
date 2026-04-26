import { DateField } from "@refinedev/antd";
import { useList } from "@refinedev/core";
import {
  Avatar,
  Card,
  Col,
  Empty,
  List as AntList,
  Row,
  Space,
  Statistic,
  Table,
  Tag,
  Typography,
} from "antd";
import type { AppUser, CoinEntry, MetricEntry } from "../../types";

const { Title, Text } = Typography;

const KIND_COLOR: Record<CoinEntry["kind"], string> = {
  purchase: "geekblue",
  bonus: "green",
  refund: "purple",
  spend: "volcano",
};
const KIND_LABEL: Record<CoinEntry["kind"], string> = {
  purchase: "결제",
  bonus: "보너스",
  refund: "환불",
  spend: "사용",
};

const DAY_MS = 86_400_000;

export const DashboardPage = () => {
  const { result: usersResult } = useList<AppUser>({
    resource: "users",
    pagination: { mode: "off" },
  });
  const { result: metricsResult } = useList<MetricEntry>({
    resource: "metrics",
    pagination: { mode: "off" },
  });
  const { result: coinsResult } = useList<CoinEntry>({
    resource: "coins",
    pagination: { mode: "off" },
  });

  const users = usersResult?.data ?? [];
  const metrics = metricsResult?.data ?? [];
  const coins = coinsResult?.data ?? [];

  const now = Date.now();
  const cutoff7 = now - 7 * DAY_MS;
  const cutoff30 = now - 30 * DAY_MS;

  const newUsers7 = users.filter(
    (u) => new Date(u.created_at).getTime() >= cutoff7
  ).length;
  const newUsers30 = users.filter(
    (u) => new Date(u.created_at).getTime() >= cutoff30
  ).length;
  const skippedBonusCount = users.filter((u) => u.signup_bonus_skipped).length;

  const newMetrics7 = metrics.filter(
    (m) => new Date(m.created_at).getTime() >= cutoff7
  ).length;

  const totalPurchased = coins
    .filter((c) => c.kind === "purchase")
    .reduce((s, c) => s + c.amount, 0);
  const totalSpent = coins
    .filter((c) => c.kind === "spend")
    .reduce((s, c) => s + Math.abs(c.amount), 0);
  const totalBonus = coins
    .filter((c) => c.kind === "bonus")
    .reduce((s, c) => s + c.amount, 0);
  const totalRefund = coins
    .filter((c) => c.kind === "refund")
    .reduce((s, c) => s + c.amount, 0);
  const totalBalance = users.reduce((s, u) => s + (u.coins ?? 0), 0);

  const recentSignups = [...users]
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
    .slice(0, 8);

  const recentTxs = [...coins]
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
    .slice(0, 10);
  const userById = new Map<string, AppUser>(users.map((u) => [u.id, u]));

  const sourceCounts = metrics.reduce<Record<string, number>>((acc, m) => {
    acc[m.source] = (acc[m.source] ?? 0) + 1;
    return acc;
  }, {});
  const genderCounts = metrics.reduce<Record<string, number>>((acc, m) => {
    acc[m.gender] = (acc[m.gender] ?? 0) + 1;
    return acc;
  }, {});

  return (
    <Space direction="vertical" size={16} style={{ width: "100%" }}>
      <Title level={3} style={{ margin: 0 }}>
        Face Reader 운영 대시보드
      </Title>

      <Row gutter={[12, 12]}>
        <Col xs={12} md={6}>
          <Card>
            <Statistic title="총 가입자" value={users.length} suffix="명" />
            <Text type="secondary" style={{ fontSize: 12 }}>
              7일 신규 +{newUsers7} · 30일 +{newUsers30}
            </Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card>
            <Statistic
              title="총 metric 업로드"
              value={metrics.length}
              valueStyle={{ color: "#0958d9" }}
            />
            <Text type="secondary" style={{ fontSize: 12 }}>
              7일 +{newMetrics7}
            </Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card>
            <Statistic
              title="총 코인 매출"
              value={totalPurchased}
              valueStyle={{ color: "#1677ff" }}
            />
            <Text type="secondary" style={{ fontSize: 12 }}>
              환불 보정 −{totalRefund > 0 ? totalRefund : 0}
            </Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card>
            <Statistic
              title="총 코인 소비"
              value={totalSpent}
              valueStyle={{ color: "#cf1322" }}
            />
            <Text type="secondary" style={{ fontSize: 12 }}>
              궁합 unlock 등 spend 합
            </Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card>
            <Statistic
              title="보너스 발급"
              value={totalBonus}
              valueStyle={{ color: "#389e0d" }}
            />
            <Text type="secondary" style={{ fontSize: 12 }}>
              dedup skip {skippedBonusCount}명
            </Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card>
            <Statistic
              title="유통중 잔액 합"
              value={totalBalance}
              valueStyle={{ color: "#d4380d" }}
            />
            <Text type="secondary" style={{ fontSize: 12 }}>
              users.coins SoT 합산
            </Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card>
            <Statistic
              title="metric source"
              value={`📷 ${sourceCounts.camera ?? 0} / 🖼️ ${sourceCounts.album ?? 0}`}
            />
            <Text type="secondary" style={{ fontSize: 12 }}>
              camera / album
            </Text>
          </Card>
        </Col>
        <Col xs={12} md={6}>
          <Card>
            <Statistic
              title="metric 성별"
              value={`♂ ${genderCounts.male ?? 0} / ♀ ${genderCounts.female ?? 0}`}
            />
            <Text type="secondary" style={{ fontSize: 12 }}>
              male / female
            </Text>
          </Card>
        </Col>
      </Row>

      <Row gutter={[16, 16]}>
        <Col xs={24} lg={10}>
          <Card title="최근 가입자">
            {recentSignups.length === 0 ? (
              <Empty />
            ) : (
              <AntList
                dataSource={recentSignups}
                renderItem={(u) => (
                  <AntList.Item>
                    <AntList.Item.Meta
                      avatar={
                        <Avatar src={u.profile_image_url ?? undefined}>
                          {u.nickname?.[0] ?? "?"}
                        </Avatar>
                      }
                      title={
                        <Space>
                          <Text strong>{u.nickname ?? "(닉네임 없음)"}</Text>
                          {u.signup_bonus_skipped && (
                            <Tag color="warning">bonus skipped</Tag>
                          )}
                        </Space>
                      }
                      description={
                        <Space size={12}>
                          <DateField
                            value={u.created_at}
                            format="YYYY-MM-DD HH:mm"
                          />
                          <Text type="secondary">잔액 {u.coins} 🪙</Text>
                        </Space>
                      }
                    />
                  </AntList.Item>
                )}
              />
            )}
          </Card>
        </Col>
        <Col xs={24} lg={14}>
          <Card title="최근 코인 거래">
            {recentTxs.length === 0 ? (
              <Empty />
            ) : (
              <Table
                dataSource={recentTxs}
                rowKey="id"
                size="small"
                pagination={false}
              >
                <Table.Column<CoinEntry>
                  title="사용자"
                  dataIndex="user_id"
                  render={(uid: string) => {
                    const u = userById.get(uid);
                    return (
                      <Space>
                        <Avatar src={u?.profile_image_url ?? undefined} size={20}>
                          {u?.nickname?.[0] ?? "?"}
                        </Avatar>
                        <Text>{u?.nickname ?? uid.slice(0, 8) + "…"}</Text>
                      </Space>
                    );
                  }}
                />
                <Table.Column<CoinEntry>
                  title="kind"
                  dataIndex="kind"
                  render={(k: CoinEntry["kind"]) => (
                    <Tag color={KIND_COLOR[k]}>{KIND_LABEL[k]}</Tag>
                  )}
                />
                <Table.Column<CoinEntry>
                  title="Δ"
                  dataIndex="amount"
                  align="right"
                  render={(v: number) => (
                    <Text strong style={{ color: v < 0 ? "#cf1322" : "#1677ff" }}>
                      {v > 0 ? "+" : ""}
                      {v}
                    </Text>
                  )}
                />
                <Table.Column<CoinEntry>
                  title="잔액"
                  dataIndex="balance_after"
                  align="right"
                />
                <Table.Column<CoinEntry>
                  title="시각"
                  dataIndex="created_at"
                  render={(v: string) => (
                    <DateField value={v} format="MM-DD HH:mm" />
                  )}
                />
              </Table>
            )}
          </Card>
        </Col>
      </Row>
    </Space>
  );
};
