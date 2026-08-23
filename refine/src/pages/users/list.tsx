import { DeleteOutlined } from "@ant-design/icons";
import { PAGE_SIZE } from "../../constants";
import {
  DateField,
  List,
  NumberField,
  ShowButton,
  useTable,
} from "@refinedev/antd";
import { type BaseRecord, useInvalidate } from "@refinedev/core";
import {
  Avatar,
  Button,
  Popconfirm,
  Space,
  Table,
  Tag,
  Typography,
  message,
} from "antd";
import { UserLink } from "../../components/user-link";
import { deleteR2Object, deleteR2Prefix } from "../../lib/r2";
import { adminClient } from "../../providers/data";
import type { AppUser } from "../../types";

const { Text } = Typography;

export const UserList = () => {
  const { tableProps } = useTable<AppUser>({
    resource: "admin_users",
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
    pagination: { pageSize: PAGE_SIZE },
  });

  const invalidate = useInvalidate();

  /** 회원 탈퇴 — web /api/account/delete 와 동일 순서:
   *  썸네일 수집 → R2 삭제 → metrics 삭제 → 모집 중 teams 삭제 →
   *  auth.users 삭제 (cascade: users/coins/compatibilities). */
  const handleDelete = async (record: AppUser) => {
    try {
      // 사진은 `thumbnails/{uid}/` 폴더 통째로 — body 의 *현재* 키만 세면
      // 재촬영으로 남은 옛 사진이 그대로 남는다(탈퇴 고지 위반). 소유자 스코프
      // 이전에 저장된 레거시 키만 body 에서 따로 걷는다.
      // 이 사람이 **구매한** 궁합의 사본도 같은 폴더라 함께 사라진다 — 맞다.
      // 반대로 남이 이 사람 얼굴을 사서 뜬 사본은 그쪽 폴더라 살아남는다.
      const { data: rows } = await adminClient
        .from("metrics")
        .select("body")
        .eq("user_id", record.id);
      const legacy: string[] = [];
      for (const r of rows ?? []) {
        try {
          const b = JSON.parse(r.body as string) as { thumbnailKey?: string };
          if (b.thumbnailKey && !b.thumbnailKey.startsWith(`thumbnails/${record.id}/`)) {
            legacy.push(b.thumbnailKey);
          }
        } catch {
          /* malformed body — skip */
        }
      }
      const removed = await deleteR2Prefix(`thumbnails/${record.id}/`);
      await Promise.all(legacy.map((k) => deleteR2Object(k)));
      console.log(`[users] 썸네일 삭제 ${removed}개 + 레거시 ${legacy.length}개`);

      const { error: metricsErr } = await adminClient
        .from("metrics")
        .delete()
        .eq("user_id", record.id);
      if (metricsErr) {
        message.error(`metrics 삭제 실패: ${metricsErr.message}`);
        return;
      }
      // 모집 중(open) 그룹만 — closed 팀은 owner_id 만 null 로 남아 결과 열람 유지.
      const { error: teamsErr } = await adminClient
        .from("teams")
        .delete()
        .eq("owner_id", record.id)
        .is("closed_at", null);
      if (teamsErr) {
        message.error(`모집 중 그룹 삭제 실패: ${teamsErr.message}`);
        return;
      }
      const { error: authErr } = await adminClient.auth.admin.deleteUser(
        record.id,
      );
      if (authErr) {
        message.error(`auth 사용자 삭제 실패: ${authErr.message}`);
        return;
      }
      message.success("탈퇴 처리됨");
      invalidate({ resource: "admin_users", invalidates: ["list"] });
    } catch (e) {
      message.error(`삭제 실패: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  return (
    <List title="사용자 리스트">
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
          render={(v: string | null, record: AppUser) => (
            <UserLink id={record.id}>
              {v ? <Text strong>{v}</Text> : <Text type="secondary">-</Text>}
            </UserLink>
          )}
        />
        <Table.Column
          title="이메일"
          dataIndex="email"
          render={(v: string | null) =>
            v ? (
              <Text style={{ fontSize: 12 }}>{v}</Text>
            ) : (
              <Text type="secondary">—</Text>
            )
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
          title="메뉴"
          dataIndex="actions"
          render={(_, record: BaseRecord) => (
            <Space size={4}>
              <ShowButton hideText size="small" recordItemId={record.id} />
              <Popconfirm
                title="회원 탈퇴"
                description={`'${(record as AppUser).nickname ?? "(없음)"}' 을 탈퇴 처리합니다. 관상·R2 썸네일·코인·궁합·모집 중 그룹이 삭제되며 되돌릴 수 없습니다.`}
                okText="Yes"
                cancelText="No"
                okButtonProps={{ danger: true }}
                onConfirm={() => handleDelete(record as AppUser)}
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
