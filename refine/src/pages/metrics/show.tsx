import { Show } from "@refinedev/antd";
import { useShow } from "@refinedev/core";
import { Alert, Descriptions, Space, Tag, Typography } from "antd";
import { useMemo } from "react";
import type { MetricEntry } from "../../types";
import { runEngine, type EngineOutput } from "../../lib/share-engine";
import { SoloHeroCard } from "./HeroCard";

const { Text } = Typography;

const SOURCE_COLOR: Record<string, string> = { camera: "blue", album: "green" };
const GENDER_LABEL: Record<string, string> = { male: "남", female: "여" };

export const MetricShow = () => {
  const { query } = useShow<MetricEntry>();
  const row = query?.data?.data;

  const result = useMemo<{ eng?: EngineOutput; error?: string }>(() => {
    if (!row?.metrics_json) return {};
    try {
      return { eng: runEngine(row.metrics_json) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [row?.metrics_json]);

  return (
    <Show isLoading={query.isLoading} title="관상 해석">
      {row && (
        <Space direction="vertical" size="large" style={{ width: "100%" }}>
          <Descriptions column={2} bordered size="small">
            <Descriptions.Item label="ID">
              <Text code copyable={{ text: row.id }} style={{ fontSize: 12 }}>
                {row.id}
              </Text>
            </Descriptions.Item>
            <Descriptions.Item label="user_id">
              <Text code style={{ fontSize: 12 }}>
                {row.user_id ?? "anon"}
              </Text>
            </Descriptions.Item>
            <Descriptions.Item label="source">
              <Tag color={SOURCE_COLOR[row.source] ?? "default"}>{row.source}</Tag>
            </Descriptions.Item>
            <Descriptions.Item label="ethnicity">{row.ethnicity}</Descriptions.Item>
            <Descriptions.Item label="성별">{GENDER_LABEL[row.gender] ?? row.gender}</Descriptions.Item>
            <Descriptions.Item label="연령대">{row.age_group}</Descriptions.Item>
            <Descriptions.Item label="alias">{row.alias ?? "-"}</Descriptions.Item>
            <Descriptions.Item label="created_at">{row.created_at}</Descriptions.Item>
            <Descriptions.Item label="expires_at" span={2}>
              {row.expires_at}
            </Descriptions.Item>
          </Descriptions>

          {result.error && (
            <Alert
              type="error"
              showIcon
              message="엔진 실행 실패"
              description={
                <Text code style={{ whiteSpace: "pre-wrap" }}>
                  {result.error}
                </Text>
              }
            />
          )}

          {result.eng && <SoloHeroCard eng={result.eng} />}

          {row.metrics_json && (
            <details>
              <summary style={{ cursor: "pointer", fontWeight: 600 }}>
                raw metrics_json
              </summary>
              <pre
                style={{
                  fontSize: 11,
                  background: "#fafafa",
                  padding: 12,
                  borderRadius: 6,
                  overflow: "auto",
                  maxHeight: 360,
                }}
              >
                {prettify(row.metrics_json)}
              </pre>
            </details>
          )}
        </Space>
      )}
    </Show>
  );
};

function prettify(json: string): string {
  try {
    return JSON.stringify(JSON.parse(json), null, 2);
  } catch {
    return json;
  }
}
