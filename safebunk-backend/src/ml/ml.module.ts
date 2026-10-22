import { Module } from '@nestjs/common';
import { HttpModule } from '@nestjs/axios';
import { ML_CLIENT_CONFIG } from './ml.constants';
import { readMlClientConfig } from './ml.config';
import { MlClientService } from './ml-client.service';
import { MlSuggestionsService } from './ml-suggestions.service';
import { MlController } from './ml.controller';
import { StaffMlController } from './staff-ml.controller';

@Module({
  imports: [HttpModule],
  controllers: [MlController, StaffMlController],
  providers: [
    {
      provide: ML_CLIENT_CONFIG,
      useFactory: () => readMlClientConfig(),
    },
    MlClientService,
    MlSuggestionsService,
  ],
  exports: [MlClientService],
})
export class MlModule {}
