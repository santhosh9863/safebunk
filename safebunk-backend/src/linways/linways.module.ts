import { Global, Module } from '@nestjs/common';
import { HttpModule } from '@nestjs/axios';
import { LinwaysService } from './linways.service';

@Global()
@Module({
  imports: [HttpModule],
  providers: [LinwaysService],
  exports: [LinwaysService],
})
export class LinwaysModule {}
