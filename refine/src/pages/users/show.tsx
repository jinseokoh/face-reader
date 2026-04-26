import { DateField, NumberField, Show } from "@refinedev/antd";
import { useList, useShow } from "@refinedev/core";
import {
  Avatar,
  Card,
  Col,
  Descriptions,
  Empty,
  Row,
  Statistic,
  Table,
  Tag,
  Typography,
} from "antd";
import type { AppUser, CoinEntry, MetricEntry, Unlock } from "../../types";

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

export const UserShow = () => {
  const {
    result: user,
    query: { isLoading },
  } = useShow<AppUser>();

  const userId = user?.id;

  const { result: metricsResult } = useList<MetricEntry>({
    resource: "metrics",
    filters: userId ? [{ field: "user_id", operator: "eq", value: userId }] : [],
    sorters: [{ field: "created_at", order: "desc" }],
    pagination: { pageSize: 50 },
    queryOptions: { enabled: !!userId },
  });

  const { result: coinsResult } = useList<CoinEntry>({
    resource: "coins",
    filters: userId ? [{ field: "user_id", operator: "eq", value: userId }] : [],
    sorters: [{ field: "created_at", order: "desc" }],
    pagination: { pageSize: 100 },
    queryOptions: { enabled: !!userId },
  });

  const { result: unlocksResult } = useList<Unlock>({
    resource: "unlocks",
    filters: userId ? [{ field: "user_id", operator: "eq", value: userId }] : [],
    sorters: [{ field: "created_at", order: "desc" }],
    pagination: { pageSize: 50 },
    queryOptions: { enabled: !!userId },
  });

  const metrics = metricsResult?.data ?? [];
  const coins = coinsResult?.data ?? [];
  const unlocks = unlocksResult?.data ?? [];

  const totalPurchased = coins
    .filter((c) => c.kind === "purchase")
    .reduce((s, c) => s + c.amount, 0);
  const totalSpent = coins
    .filter((c) => c.kind === "spend")
    .reduce((s, c) => s + Math.abs(c.amount), 0);
  const totalBonus = coins
    .filter((c) => c.kind === "bonus")
    .reduce((s, c) => s + c.amount, 0);

  return (
    <Show isLoading={isLoading} title="사용자 상세">
      <Row gutter={[16, 16]}>
        <Col xs={24} md={8}>
          <Card>
            <div style={{ textAlign: "center", marginBottom: 16 }}>
              <Avatar
                size={96}
                src={user?.profile_image_url ?? undefined}
                style={{ marginBottom: 12 }}
              >
                {user?.nickname?.[0] ?? "?"}
              </Avatar>
              <Title level={4} style={{ margin: 0 }}>
                {user?.nickname ?? "(닉네임 없음)"}
              </Title>
              {user?.signup_bonus_skipped ? (
                <Tag color="warning" style={{ marginTop: 8 }}>
                  보너스 skip — 재가입 dedup
                </Tag>
              ) : (
                <Tag color="success" style={{ marginTop: 8 }}>
                  보너스 3 코인 수령
                </Tag>
              )}
            </div>
            <Descriptions column={1} size="small">
              <Descriptions.Item label="UUID">
                <Text code copyable style={{ fontSize: 11 }}>
                  {user?.id}
                </Text>
              </Descriptions.Item>
              <Descriptions.Item label="Kakao ID">
                <Text code style={{ fontSize: 11 }}>
                  {user?.kakao_user_id ?? "-"}
                </Text>
              </Descriptions.Item>
              <Descriptions.Item label="가입일">
                {user?.created_at && (
                  <DateField value={user.created_at} format="YYYY-MM-DD HH:mm" />
                )}
              </Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>

        <Col xs={24} md={16}>
          <Row gutter={[12, 12]}>
            <Col xs={12} md={6}>
              <Card>
                <Statistic title="현재 잔액" value={user?.coins ?? 0} suffix="🪙" />
              </Card>
            </Col>
            <Col xs={12} md={6}>
              <Card>
                <Statistic
                  title="총 결제"
                  value={totalPurchased}
                  valueStyle={{ color: "#1677ff" }}
                />
              </Card>
            </Col>
            <Col xs={12} md={6}>
              <Card>
                <Statistic
                  title="총 사용"
                  value={totalSpent}
                  valueStyle={{ color: "#cf1322" }}
                />
              </Card>
            </Col>
            <Col xs={12} md={6}>
              <Card>
                <Statistic
                  title="보너스"
                  value={totalBonus}
                  valueStyle={{ color: "#389e0d" }}
                />
              </Card>
            </Col>
            <Col xs={12} md={6}>
              <Card>
                <Statistic title="metric 업로드" value={metrics.length} />
              </Card>
            </Col>
            <Col xs={12} md={6}>
              <Card>
                <Statistic title="궁합 unlock" value={unlocks.length} />
              </Card>
            </Col>
            <Col xs={12} md={12}>
              <Card>
                <Statistic title="코인 거래수" value={coins.length} />
              </Card>
            </Col>
          </Row>
        </Col>
      </Row>

      <Card title={`코인 ledger (${coins.length}건)`} style={{ marginTop: 16 }}>
        {coins.length === 0 ? (
          <Empty description="거래 없음" />
        ) : (
          <Table
            dataSource={coins}
            rowKey="id"
            size="small"
            pagination={{ pageSize: 20, showSizeChanger: true }}
          >
            <Table.Column<CoinEntry>
              title="kind"
              dataIndex="kind"
              render={(k: CoinEntry["kind"]) => (
                <Tag color={KIND_COLOR[k]}>{KIND_LABEL[k]}</Tag>
              )}
            />
            <Table.Column<CoinEntry>
              title="amount"
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
              render={(v: number) => <NumberField value={v} />}
            />
            <Table.Column<CoinEntry>
              title="product"
              dataIndex="product_id"
              render={(v: string | null) => v ?? <Text type="secondary">-</Text>}
            />
            <Table.Column<CoinEntry>
              title="reference"
              dataIndex="reference_id"
              render={(v: string | null) =>
                v ? (
                  <Text code style={{ fontSize: 11 }}>
                    {v}
                  </Text>
                ) : (
                  <Text type="secondary">-</Text>
                )
              }
            />
            <Table.Column<CoinEntry>
              title="설명"
              dataIndex="description"
              render={(v: string | null) => v ?? <Text type="secondary">-</Text>}
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

      <Card title={`metric 업로드 (${metrics.length}건)`} style={{ marginTop: 16 }}>
        {metrics.length === 0 ? (
          <Empty description="metric 없음" />
        ) : (
          <Table
            dataSource={metrics}
            rowKey="id"
            size="small"
            pagination={{ pageSize: 20 }}
          >
            <Table.Column<MetricEntry>
              title="source"
              dataIndex="source"
              render={(v: MetricEntry["source"]) => (
                <Tag color={v === "camera" ? "blue" : "green"}>{v}</Tag>
              )}
            />
            <Table.Column<MetricEntry> title="gender" dataIndex="gender" />
            <Table.Column<MetricEntry> title="age" dataIndex="age_group" />
            <Table.Column<MetricEntry> title="ethnicity" dataIndex="ethnicity" />
            <Table.Column<MetricEntry>
              title="alias"
              dataIndex="alias"
              render={(v: string | null) => v ?? <Text type="secondary">-</Text>}
            />
            <Table.Column<MetricEntry>
              title="만료"
              dataIndex="expires_at"
              render={(v: string) => (
                <DateField value={v} format="MM-DD HH:mm" />
              )}
            />
            <Table.Column<MetricEntry>
              title="업로드"
              dataIndex="created_at"
              render={(v: string) => (
                <DateField value={v} format="MM-DD HH:mm" />
              )}
            />
          </Table>
        )}
      </Card>

      {unlocks.length > 0 && (
        <Card title={`궁합 unlock (${unlocks.length}건)`} style={{ marginTop: 16 }}>
          <Table dataSource={unlocks} rowKey="pair_key" size="small">
            <Table.Column<Unlock>
              title="pair_key"
              dataIndex="pair_key"
              render={(v: string) => (
                <Text code style={{ fontSize: 11 }}>
                  {v}
                </Text>
              )}
            />
            <Table.Column<Unlock>
              title="시각"
              dataIndex="created_at"
              render={(v: string) => (
                <DateField value={v} format="YYYY-MM-DD HH:mm" />
              )}
            />
          </Table>
        </Card>
      )}
    </Show>
  );
};
