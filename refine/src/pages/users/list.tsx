import {
  DateField,
  List,
  NumberField,
  ShowButton,
  useTable,
} from "@refinedev/antd";
import type { BaseRecord } from "@refinedev/core";
import { Avatar, Space, Table, Tag, Typography } from "antd";
import type { AppUser } from "../../types";

const { Text } = Typography;

export const UserList = () => {
  const { tableProps } = useTable<AppUser>({
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
  });

  return (
    <List title="가입자">
      <Table {...tableProps} rowKey="id" size="middle">
        <Table.Column
          title=""
          dataIndex="profile_image_url"
          width={56}
          render={(value: string | null, record: AppUser) => (
            <Avatar src={value ?? undefined} size={36}>
              {record.nickname?.[0] ?? "?"}
            </Avatar>
          )}
        />
        <Table.Column
          title="닉네임"
          dataIndex="nickname"
          render={(v: string | null) =>
            v ? <Text strong>{v}</Text> : <Text type="secondary">-</Text>
          }
        />
        <Table.Column
          title="Kakao ID"
          dataIndex="kakao_user_id"
          render={(v: string | null) =>
            v ? (
              <Text code style={{ fontSize: 12 }}>
                {v}
              </Text>
            ) : (
              <Text type="secondary">-</Text>
            )
          }
        />
        <Table.Column<AppUser>
          title="코인 잔액"
          dataIndex="coins"
          sorter
          align="right"
          render={(v: number) => (
            <NumberField
              value={v}
              options={{ maximumFractionDigits: 0 }}
            />
          )}
        />
        <Table.Column<AppUser>
          title="보너스"
          dataIndex="signup_bonus_skipped"
          render={(skipped: boolean) =>
            skipped ? (
              <Tag color="warning">skipped (재가입)</Tag>
            ) : (
              <Tag color="success">3 코인 지급</Tag>
            )
          }
        />
        <Table.Column<AppUser>
          title="가입일"
          dataIndex="created_at"
          sorter
          defaultSortOrder="descend"
          render={(v: string) => <DateField value={v} format="YYYY-MM-DD HH:mm" />}
        />
        <Table.Column<AppUser>
          title="UUID"
          dataIndex="id"
          render={(v: string) => (
            <Text code copyable={{ text: v }} style={{ fontSize: 11 }}>
              {v.slice(0, 8)}…
            </Text>
          )}
        />
        <Table.Column
          title=""
          dataIndex="actions"
          render={(_, record: BaseRecord) => (
            <Space>
              <ShowButton hideText size="small" recordItemId={record.id} />
            </Space>
          )}
        />
      </Table>
    </List>
  );
};
