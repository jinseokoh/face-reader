import { DateField, List, NumberField, useTable } from "@refinedev/antd";
import { useMany } from "@refinedev/core";
import { Avatar, Space, Table, Tag, Tooltip, Typography } from "antd";
import type { AppUser, CoinEntry } from "../../types";

const { Text } = Typography;

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

export const CoinList = () => {
  const { tableProps, result } = useTable<CoinEntry>({
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
    filters: { mode: "server" },
  });

  const userIds = (result?.data ?? [])
    .map((c) => c.user_id)
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

  return (
    <List title="코인 ledger">
      <Table {...tableProps} rowKey="id" size="middle" scroll={{ x: 1200 }}>
        <Table.Column<CoinEntry>
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
        <Table.Column<CoinEntry>
          title="kind"
          dataIndex="kind"
          filters={[
            { text: "결제", value: "purchase" },
            { text: "보너스", value: "bonus" },
            { text: "사용", value: "spend" },
            { text: "환불", value: "refund" },
          ]}
          render={(k: CoinEntry["kind"]) => (
            <Tag color={KIND_COLOR[k]}>{KIND_LABEL[k]}</Tag>
          )}
        />
        <Table.Column<CoinEntry>
          title="amount"
          dataIndex="amount"
          align="right"
          sorter
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
          title="store_tx"
          dataIndex="store_transaction_id"
          render={(v: string | null) =>
            v ? (
              <Tooltip title={v}>
                <Text code style={{ fontSize: 11 }}>
                  {v.slice(0, 12)}…
                </Text>
              </Tooltip>
            ) : (
              <Text type="secondary">-</Text>
            )
          }
        />
        <Table.Column<CoinEntry>
          title="reference"
          dataIndex="reference_id"
          render={(v: string | null) =>
            v ? (
              <Tooltip title={v}>
                <Text code style={{ fontSize: 11 }}>
                  {v.length > 18 ? v.slice(0, 18) + "…" : v}
                </Text>
              </Tooltip>
            ) : (
              <Text type="secondary">-</Text>
            )
          }
        />
        <Table.Column<CoinEntry>
          title="설명"
          dataIndex="description"
          render={(v: string | null) =>
            v ?? <Text type="secondary">-</Text>
          }
        />
        <Table.Column<CoinEntry>
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
