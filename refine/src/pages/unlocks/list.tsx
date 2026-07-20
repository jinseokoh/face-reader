import { DeleteOutlined } from "@ant-design/icons";
import { DateField, List, ShowButton, useTable } from "@refinedev/antd";
import { useInvalidate, useMany } from "@refinedev/core";
import {
  Avatar,
  Button,
  Popconfirm,
  Space,
  Table,
  Tag,
  Tooltip,
  Typography,
  message,
} from "antd";
import { UserLink } from "../../components/user-link";
import { adminClient } from "../../providers/data";
import type { AppUser, Unlock } from "../../types";

const { Text } = Typography;

// 경계는 shared/compat_label.dart kCompatLabelThresholds (90.5/81.5/61.5) 미러.
function scoreColor(s: number): string {
  if (s >= 90.5) return "magenta"; // 천생연분
  if (s >= 81.5) return "geekblue"; // 금슬화합
  if (s >= 61.5) return "green"; // 상부상조
  return "default"; // 형극난조
}

function scoreLabel(s: number): string {
  if (s >= 90.5) return "천생연분";
  if (s >= 81.5) return "금슬화합";
  if (s >= 61.5) return "상부상조";
  return "형극난조";
}

export const UnlockList = () => {
  const { tableProps, result } = useTable<Unlock>({
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
  });

  const userIds = (result?.data ?? []).map((u) => u.user_id);

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

  const invalidate = useInvalidate();

  /** unlock 삭제 — (user_id, a_id, b_id) 복합 키. 스냅샷 body 도 함께 사라져
   *  사용자는 재열람에 코인을 다시 써야 한다. */
  const handleDelete = async (r: Unlock) => {
    const { error } = await adminClient
      .from("unlocks")
      .delete()
      .eq("user_id", r.user_id)
      .eq("a_id", r.a_id)
      .eq("b_id", r.b_id);
    if (error) {
      message.error(`삭제 실패: ${error.message}`);
      return;
    }
    message.success("궁합 unlock 삭제됨");
    invalidate({ resource: "unlocks", invalidates: ["list"] });
  };

  return (
    <List title="궁합 리스트">
      <Table
        {...tableProps}
        rowKey={(r) => `${r.user_id}~${r.a_id}~${r.b_id}`}
        size="middle"
        scroll={{ x: 1100 }}
      >
        <Table.Column<Unlock>
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
                <UserLink id={uid}><Text strong>{u.nickname ?? "(없음)"}</Text></UserLink>
              </Space>
            );
          }}
        />
        <Table.Column<Unlock>
          title="점수"
          dataIndex="total_score"
          sorter
          render={(v: number | null) => {
            if (v == null) return <Text type="secondary">-</Text>;
            const s = Number(v);
            return (
              <Tooltip title={scoreLabel(s)}>
                <Tag color={scoreColor(s)}>{s.toFixed(1)}</Tag>
              </Tooltip>
            );
          }}
        />
        <Table.Column<Unlock>
          title="궁합 쌍"
          dataIndex="a_id"
          render={(_: string, r: Unlock) => (
            <Space size={4}>
              <Text strong>{r.a_alias ?? "(이름 없음)"}</Text>
              <Text type="secondary">·</Text>
              <Text strong>{r.b_alias ?? "(이름 없음)"}</Text>
            </Space>
          )}
        />
        <Table.Column<Unlock>
          title="해제 시각"
          dataIndex="created_at"
          sorter
          defaultSortOrder="descend"
          render={(v: string) => (
            <DateField value={v} format="YYYY-MM-DD HH:mm" />
          )}
        />
        <Table.Column<Unlock>
          title="메뉴"
          dataIndex="a_id"
          fixed="right"
          render={(_: string, r: Unlock) => (
            <Space size={4}>
              {/* 복합 키를 단일 route param 으로 — show 가 ~ 로 다시 쪼갠다. */}
              <ShowButton
                hideText
                size="small"
                recordItemId={`${r.user_id}~${r.a_id}~${r.b_id}`}
              />
              <Popconfirm
                title="궁합 unlock 삭제"
                description="이 궁합 잠금해제 기록을 삭제합니다. 사용자가 다시 보려면 코인을 재차감해야 하며 되돌릴 수 없습니다."
                okText="Yes"
                cancelText="No"
                okButtonProps={{ danger: true }}
                onConfirm={() => handleDelete(r)}
              >
                <Button size="small" danger icon={<DeleteOutlined />} />
              </Popconfirm>
            </Space>
          )}
        />
      </Table>
    </List>
  );
};
