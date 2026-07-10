import { DownloadOutlined } from '@ant-design/icons';
import { Button, Typography } from 'antd';
import React, { useCallback } from 'react';
import { useTranslation } from 'react-i18next';

import { downloadVisFile, VisFileDownloadData } from '@/utils/vis-file-download';

const VisFileDownload: React.FC<{ data: VisFileDownloadData }> = ({ data }) => {
  const { t } = useTranslation();

  const handleDownload = useCallback(() => {
    if (!data?.content_base64) {
      return;
    }
    downloadVisFile(data);
  }, [data]);

  if (!data) {
    return null;
  }

  return (
    <div className='flex items-center gap-3 p-3 border rounded-md w-fit'>
      <Typography.Text>{data.filename}</Typography.Text>
      <Button type='primary' size='small' icon={<DownloadOutlined />} onClick={handleDownload}>
        {t('Download', { defaultValue: '下载' })}
      </Button>
    </div>
  );
};

export default VisFileDownload;
