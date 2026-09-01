Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\BeeLlamaManager.Core.psm1') -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\BeeForgeTeam.Core.psm1') -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\BeeForgeTelegram.Core.psm1') -Force
try { Invoke-BeeRetention } catch {}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="BeeForge AI Console" Height="860" Width="1260" MinHeight="720" MinWidth="1060" WindowStartupLocation="CenterScreen" Background="#111318" Foreground="#E8ECF2">
 <Window.Resources>
  <Style TargetType="TextBox"><Setter Property="Margin" Value="5"/><Setter Property="Padding" Value="7"/><Setter Property="Background" Value="#20242C"/><Setter Property="Foreground" Value="#F3F5F7"/><Setter Property="BorderBrush" Value="#3A414D"/></Style>
  <Style TargetType="ComboBox"><Setter Property="Margin" Value="5"/><Setter Property="Padding" Value="5"/><Setter Property="Background" Value="#F4F6F8"/><Setter Property="Foreground" Value="#111318"/><Setter Property="BorderBrush" Value="#707887"/></Style>
  <Style TargetType="ComboBoxItem"><Setter Property="Background" Value="#F4F6F8"/><Setter Property="Foreground" Value="#111318"/><Setter Property="Padding" Value="7,5"/><Style.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter Property="Background" Value="#2878C8"/><Setter Property="Foreground" Value="White"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#165A9E"/><Setter Property="Foreground" Value="White"/></Trigger></Style.Triggers></Style>
  <Style TargetType="CheckBox"><Setter Property="Margin" Value="8"/><Setter Property="VerticalAlignment" Value="Center"/><Setter Property="Foreground" Value="#E8ECF2"/></Style>
  <Style TargetType="Button"><Setter Property="Margin" Value="4"/><Setter Property="Padding" Value="11,7"/><Setter Property="Background" Value="#2C3440"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderBrush" Value="#495365"/></Style>
  <Style TargetType="Label"><Setter Property="Foreground" Value="#BFC7D4"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
  <Style TargetType="GroupBox"><Setter Property="Foreground" Value="#DDE4EE"/><Setter Property="Margin" Value="8"/><Setter Property="Padding" Value="8"/></Style>
  <Style TargetType="ToolTip"><Setter Property="Background" Value="#252B35"/><Setter Property="Foreground" Value="#F3F5F7"/><Setter Property="BorderBrush" Value="#596579"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="9,6"/><Setter Property="MaxWidth" Value="430"/></Style>
  <Style TargetType="DataGridColumnHeader"><Setter Property="Background" Value="#2C3440"/><Setter Property="Foreground" Value="#F3F5F7"/><Setter Property="BorderBrush" Value="#4B5668"/><Setter Property="BorderThickness" Value="0,0,1,1"/><Setter Property="Padding" Value="8,6"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="HorizontalContentAlignment" Value="Left"/></Style>
  <Style TargetType="DataGridRowHeader"><Setter Property="Background" Value="#20242C"/><Setter Property="Foreground" Value="#F3F5F7"/><Setter Property="BorderBrush" Value="#3A414D"/></Style>
 </Window.Resources>
 <Grid Margin="12">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <DockPanel Grid.Row="0" Margin="0,0,0,8">
   <StackPanel DockPanel.Dock="Left"><TextBlock Text="BeeForge AI Console" FontSize="24" FontWeight="SemiBold"/><TextBlock Text="Локальные модели, OpenCode и производительность" Foreground="#8F9AAA"/></StackPanel>
   <Border DockPanel.Dock="Right" Background="#1B2028" CornerRadius="6" Padding="12,7"><TextBlock Name="HeaderStatus" Text="Проверка состояния..."/></Border>
  </DockPanel>
  <Grid Grid.Row="1">
   <Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border Grid.Column="0" Background="#181B21" CornerRadius="7" Padding="8" Margin="0,0,9,0">
    <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
     <TextBlock Text="ПРОФИЛИ" FontWeight="Bold" Margin="6" Foreground="#9EABC0"/>
     <ListBox Name="ProfileList" Grid.Row="1" Margin="4" Background="#111318" Foreground="White" BorderBrush="#343B46" DisplayMemberPath="name"/>
     <UniformGrid Grid.Row="2" Columns="2"><Button Name="NewProfile" Content="Новый"/><Button Name="CloneProfile" Content="Клон"/><Button Name="DeleteProfile" Content="Удалить"/><Button Name="ImportProfile" Content="Импорт"/><Button Name="ExportProfile" Content="Экспорт"/><Button Name="RefreshModels" Content="Модели"/></UniformGrid>
    </Grid>
   </Border>
   <TabControl Grid.Column="1" Name="Tabs" Background="#181B21" Foreground="White" BorderBrush="#343B46">
    <TabItem Header="Основные">
     <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
      <GroupBox Name="ProfileVisionGroup" Header="Профиль, модель и vision"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="160"/><ColumnDefinition Width="*"/><ColumnDefinition Width="105"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
       <Label Content="Имя профиля"/><TextBox Grid.Column="1" Grid.ColumnSpan="2" Name="ProfileName"/>
       <Label Grid.Row="1" Content="GGUF модель"/><ComboBox Grid.Row="1" Grid.Column="1" Name="ModelPath" IsEditable="True" IsTextSearchEnabled="True"/><Button Grid.Row="1" Grid.Column="2" Name="BrowseModel" Content="Обзор..."/>
       <Label Grid.Row="2" Content="llama-server.exe"/><TextBox Grid.Row="2" Grid.Column="1" Name="ServerPath"/><Button Grid.Row="2" Grid.Column="2" Name="BrowseRuntime" Content="Обзор..."/>
       <Label Grid.Row="3" Content="API alias"/><TextBox Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="2" Name="Alias"/>
       <Label Grid.Row="4" Content="Vision projector"/><ComboBox Grid.Row="4" Grid.Column="1" Name="MmprojPath" IsEditable="True" ToolTip="Совместимый mmproj*.gguf; автоматически ищется рядом с моделью"/><Button Grid.Row="4" Grid.Column="2" Name="BrowseMmproj" Content="Обзор..."/>
       <Label Grid.Row="5" Content="Изображения"/><StackPanel Grid.Row="5" Grid.Column="1" Grid.ColumnSpan="2" Orientation="Horizontal"><CheckBox Name="VisionEnabled" Content="Включить vision для этой модели"/><CheckBox Name="VisionOffload" Content="Projector на GPU" ToolTip="Выключено: projector остаётся в RAM — рекомендуется при VRAM около предела"/><TextBlock Name="VisionHint" Text="Выберите совместимый mmproj projector" Foreground="#FFBA69" VerticalAlignment="Center" TextWrapping="Wrap" Margin="7,3"/></StackPanel>
      </Grid></GroupBox>
      <GroupBox Name="ComputeGroup" Header="Контекст и вычисления"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="140"/><ColumnDefinition Width="150"/><ColumnDefinition Width="140"/><ColumnDefinition Width="150"/><ColumnDefinition Width="140"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <Label Content="Context"/><TextBox Grid.Column="1" Name="Context"/><Label Grid.Column="2" Content="GPU layers"/><ComboBox Grid.Column="3" Name="GpuLayers" MaxDropDownHeight="390" ToolTip="all — все слои; числа — уменьшение GPU offload"/><Label Grid.Column="4" Content="Parallel"/><TextBox Grid.Column="5" Name="Parallel"/>
       <Label Grid.Row="1" Content="Batch"/><TextBox Grid.Row="1" Grid.Column="1" Name="Batch"/><Label Grid.Row="1" Grid.Column="2" Content="Ubatch"/><TextBox Grid.Row="1" Grid.Column="3" Name="Ubatch"/><CheckBox Grid.Row="1" Grid.Column="4" Grid.ColumnSpan="2" Name="FlashAttention" Content="Flash Attention"/>
       <Label Grid.Row="2" Content="Threads"/><TextBox Grid.Row="2" Grid.Column="1" Name="Threads"/><Label Grid.Row="2" Grid.Column="2" Content="Threads batch"/><TextBox Grid.Row="2" Grid.Column="3" Name="ThreadsBatch"/><Label Grid.Row="2" Grid.Column="4" Content="Cache reuse"/><TextBox Grid.Row="2" Grid.Column="5" Name="CacheReuse"/>
      </Grid></GroupBox>
      <GroupBox Name="ApiGroup" Header="API"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="200"/><ColumnDefinition Width="100"/><ColumnDefinition Width="130"/><ColumnDefinition Width="160"/><ColumnDefinition Width="130"/></Grid.ColumnDefinitions>
       <Label Content="Host"/><TextBox Grid.Column="1" Name="Host"/><Label Grid.Column="2" Content="Port"/><TextBox Grid.Column="3" Name="Port"/><CheckBox Grid.Column="4" Name="OpenCodeSync" Content="Обновлять OpenCode"/><TextBox Grid.Column="5" Name="OpenCodeOutput" ToolTip="OpenCode output limit"/>
      </Grid></GroupBox>
     </StackPanel></ScrollViewer>
    </TabItem>
    <TabItem Header="Производительность">
     <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
      <GroupBox Name="KvGroup" Header="KV cache"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="180"/><ColumnDefinition Width="140"/><ColumnDefinition Width="180"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <Label Content="KV K"/><ComboBox Grid.Column="1" Name="KvK"/><Label Grid.Column="2" Content="KV V"/><ComboBox Grid.Column="3" Name="KvV"/>
       <Label Grid.Row="1" Content="KV tail tokens"/><TextBox Grid.Row="1" Grid.Column="1" Name="KvTailTokens"/><Label Grid.Row="1" Grid.Column="2" Content="KV tail type"/><ComboBox Grid.Row="1" Grid.Column="3" Name="KvTailType"/>
      </Grid></GroupBox>
      <GroupBox Name="ReasoningGroup" Header="Reasoning"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="160"/><ColumnDefinition Width="200"/><ColumnDefinition Width="160"/></Grid.ColumnDefinitions>
       <CheckBox Name="ReasoningEnabled" Content="Reasoning включён"/><TextBox Grid.Column="1" Name="ReasoningBudget" ToolTip="Hard reasoning budget"/><CheckBox Grid.Column="2" Name="ReasoningPreserve" Content="Preserve reasoning"/>
      </Grid></GroupBox>
      <GroupBox Name="MtpGroup" Header="MTP / speculative decoding"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="160"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
       <CheckBox Name="MtpEnabled" Content="MTP включён"/><ComboBox Grid.Column="1" Name="MtpNMax"/>
      </Grid></GroupBox>
      <GroupBox Name="SamplingGroup" Header="Sampling"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="130"/><ColumnDefinition Width="100"/><ColumnDefinition Width="130"/><ColumnDefinition Width="100"/><ColumnDefinition Width="130"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <Label Content="Temperature"/><TextBox Grid.Column="1" Name="Temperature"/><Label Grid.Column="2" Content="Top P"/><TextBox Grid.Column="3" Name="TopP"/><Label Grid.Column="4" Content="Top K"/><TextBox Grid.Column="5" Name="TopK"/>
       <Label Grid.Row="1" Content="Min P"/><TextBox Grid.Row="1" Grid.Column="1" Name="MinP"/><Label Grid.Row="1" Grid.Column="2" Content="Repeat penalty"/><TextBox Grid.Row="1" Grid.Column="3" Name="RepeatPenalty"/>
      </Grid></GroupBox>
     </StackPanel></ScrollViewer>
    </TabItem>
    <TabItem Header="Ресурсы" Name="ResourcesTab">
     <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="10">
      <TextBlock Text="Оценка памяти текущих значений формы" FontSize="20" FontWeight="SemiBold" Foreground="#F2F5F8" Margin="5,3,5,8"/>
      <Border Background="#18364A" BorderBrush="#3285B5" BorderThickness="1" CornerRadius="6" Padding="10" Margin="4,0,4,10"><TextBlock Text="Сохранять профиль перед расчётом не нужно. Измените параметры на вкладках «Основные» или «Производительность» — оценка обновится автоматически. Кнопка ниже нужна только для ручного обновления." TextWrapping="Wrap" Foreground="#D8F0FF"/></Border>
      <TextBlock Name="ResourceCalculatedFrom" Text="Ожидание расчёта..." Foreground="#8FC8EA" Margin="7,0,7,5"/>
      <Border Name="ResourceRiskCard" Background="#25352C" BorderBrush="#3D8B60" BorderThickness="1" CornerRadius="7" Padding="14" Margin="4"><TextBlock Name="ResourceVerdict" Text="Нажмите «Пересчитать»" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap" Foreground="White"/></Border>
      <Grid Margin="4,12,4,5"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <Border Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Размер GGUF" Foreground="#98A4B5"/><TextBlock Name="EstimateModelSize" Text="—" FontSize="21" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="1" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Ожидаемая dedicated VRAM" Foreground="#98A4B5"/><TextBlock Name="EstimateVram" Text="—" FontSize="21" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="2" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Ожидаемый запас VRAM" Foreground="#98A4B5"/><TextBlock Name="EstimateHeadroom" Text="—" FontSize="21" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Row="1" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Ожидаемый перенос весов в RAM" Foreground="#98A4B5"/><TextBlock Name="EstimateSpill" Text="—" FontSize="21" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Row="1" Grid.Column="1" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Фактическая VRAM GPU сейчас" Foreground="#98A4B5"/><TextBlock Name="ActualVram" Text="—" FontSize="21" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Row="1" Grid.Column="2" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="RAM системы сейчас" Foreground="#98A4B5"/><TextBlock Name="ActualRam" Text="—" FontSize="21" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
      </Grid>
      <GroupBox Name="ResourceBreakdownGroup" Header="Из чего складывается прогноз"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
       <Border Background="#20242C" CornerRadius="5" Padding="10" Margin="3"><StackPanel><TextBlock Text="Веса модели на GPU" Foreground="#98A4B5"/><TextBlock Name="ResourceWeights" Text="—" FontSize="18" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="1" Background="#20242C" CornerRadius="5" Padding="10" Margin="3"><StackPanel><TextBlock Text="KV cache" Foreground="#98A4B5"/><TextBlock Name="ResourceKv" Text="—" FontSize="18" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="2" Background="#20242C" CornerRadius="5" Padding="10" Margin="3"><StackPanel><TextBlock Text="Runtime / batch" Foreground="#98A4B5"/><TextBlock Name="ResourceBuffers" Text="—" FontSize="18" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="3" Background="#20242C" CornerRadius="5" Padding="10" Margin="3"><StackPanel><TextBlock Text="Фоновая VRAM" Foreground="#98A4B5"/><TextBlock Name="ResourceBackground" Text="—" FontSize="18" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
      </Grid></GroupBox>
      <Border Background="#202B38" BorderBrush="#3E5872" BorderThickness="1" CornerRadius="6" Padding="11" Margin="4"><TextBlock Name="ResourceImpact" Text="" TextWrapping="Wrap" Foreground="#D8E7F5"/></Border>
      <Border Background="#302C20" BorderBrush="#8E7937" BorderThickness="1" CornerRadius="6" Padding="11" Margin="4"><TextBlock Name="ResourceRecommendation" Text="" TextWrapping="Wrap" Foreground="#FFE4A3" FontWeight="SemiBold"/></Border>
      <TextBlock Name="ResourceDetails" Text="" TextWrapping="Wrap" Foreground="#C8D0DC" Margin="9" LineHeight="21"/>
      <Button Name="RefreshEstimate" Content="Пересчитать оценку" HorizontalAlignment="Left"/>
      <Border Background="#1B2028" CornerRadius="6" Padding="12" Margin="4,12,4,4"><TextBlock Text="Важно: GGUF не хранит готовую цифру потребления VRAM. Оценка учитывает размер файла модели, долю GPU layers, context, типы KV, KV tail, batch и MTP. Точное потребление зависит от архитектуры модели и runtime; окончательная проверка — успешная загрузка и фактические показатели без Shared GPU Memory spill." TextWrapping="Wrap" Foreground="#AEB8C7"/></Border>
     </StackPanel></ScrollViewer>
    </TabItem>
    <TabItem Header="Advanced">
     <Grid Margin="10"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <TextBlock Text="Только поддерживаемые пары флаг / значение. Управляемые UI-флаги нельзя дублировать." Foreground="#FFBA69" Margin="4"/>
      <DataGrid Grid.Row="1" Name="AdvancedGrid" AutoGenerateColumns="False" CanUserAddRows="False" Background="#15181E" Foreground="White" RowBackground="#20242C" AlternatingRowBackground="#262B34"><DataGrid.Columns><DataGridTextColumn Header="Флаг" Binding="{Binding flag}" Width="220"/><DataGridTextColumn Header="Значение (может быть пустым)" Binding="{Binding value}" Width="*"/></DataGrid.Columns></DataGrid>
      <StackPanel Grid.Row="2" Orientation="Horizontal"><Button Name="AddAdvanced" Content="Добавить"/><Button Name="RemoveAdvanced" Content="Удалить выбранное"/></StackPanel>
     </Grid>
    </TabItem>
    <TabItem Header="CLI" Name="CommandTab"><Grid Margin="10"><TextBox Name="CommandPreview" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="13"/></Grid></TabItem>
    <TabItem Header="AI-команда" Name="TeamTab">
     <Grid Margin="10"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
       <StackPanel><Border Background="#18364A" BorderBrush="#3285B5" BorderThickness="1" CornerRadius="6" Padding="10" Margin="3"><DockPanel><StackPanel DockPanel.Dock="Left"><TextBlock Name="TeamSummary" Text="Загрузка AI-команды..." FontSize="16" FontWeight="SemiBold" Foreground="White"/><TextBlock Name="TeamConfigInfo" Foreground="#A9D7F2"/></StackPanel><StackPanel DockPanel.Dock="Right" Orientation="Horizontal"><Button Name="RefreshTeam" Content="Обновить"/><Button Name="OpenTeamConfig" Content="Открыть OpenCode config"/></StackPanel></DockPanel></Border><Border Background="#1F2A20" BorderBrush="#4E7855" BorderThickness="1" CornerRadius="6" Padding="9" Margin="3"><TextBlock Text="ПОЛИТИКА КОМАНДЫ  •  вход: Team Lead  •  режим по умолчанию: FAST  •  режим задаётся обычными словами  •  одновременно: 1 субагент  •  обычный лимит: 2 исполнителя" Foreground="#BFE8C5" TextWrapping="Wrap"/></Border><Border Name="FullAccessCard" Background="#20242C" BorderBrush="#596579" BorderThickness="1" CornerRadius="6" Padding="10" Margin="3"><DockPanel><StackPanel><TextBlock Name="FullAccessStatus" Text="Полный доступ: проверка..." FontSize="15" FontWeight="SemiBold" Foreground="White"/><TextBlock Text="Все правила OpenCode временно заменяются на * = allow: любые файлы, shell, интернет, MCP, skills и делегирование без запросов." Foreground="#BFC9D7" TextWrapping="Wrap" MaxWidth="700"/></StackPanel><Button DockPanel.Dock="Right" Name="ToggleFullAccess" Content="Полный доступ" MinWidth="190" Background="#9B4D12"/></DockPanel></Border></StackPanel>
      <Grid Grid.Row="1" Margin="0,7"><Grid.ColumnDefinitions><ColumnDefinition Width="275"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Background="#14171C" BorderBrush="#343B46" BorderThickness="1" CornerRadius="6" Padding="7" Margin="3"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Text="AI-КОМАНДА" Foreground="#9EABC0" FontWeight="Bold" Margin="5"/><ListBox Grid.Row="1" Name="TeamAgentList" Background="#111318" Foreground="White" BorderBrush="#343B46" ScrollViewer.HorizontalScrollBarVisibility="Disabled"><ListBox.ItemContainerStyle><Style TargetType="ListBoxItem"><Setter Property="HorizontalContentAlignment" Value="Stretch"/></Style></ListBox.ItemContainerStyle><ListBox.ItemTemplate><DataTemplate><TextBlock Text="{Binding DisplayName}" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap" ToolTip="{Binding Description}"/></DataTemplate></ListBox.ItemTemplate><ListBox.GroupStyle><GroupStyle><GroupStyle.HeaderTemplate><DataTemplate><Border Background="#26303B" Padding="6,4" Margin="0,6,0,2"><TextBlock Text="{Binding Name}" Foreground="#74B9FF" FontWeight="Bold"/></Border></DataTemplate></GroupStyle.HeaderTemplate></GroupStyle></ListBox.GroupStyle></ListBox><UniformGrid Grid.Row="2" Columns="3"><Button Name="NewAgent" Content="Новый"/><Button Name="CloneAgent" Content="Клон"/><Button Name="DeleteAgent" Content="Удалить"/></UniformGrid></Grid></Border>
       <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto"><StackPanel>
        <Border Background="#20242C" CornerRadius="6" Padding="10" Margin="4"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="120"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/><ColumnDefinition Width="170"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
         <Label Content="ID"/><TextBox Grid.Column="1" Name="AgentId" IsReadOnly="True"/><TextBlock Grid.Column="2" Name="AgentStatusBadge" VerticalAlignment="Center" HorizontalAlignment="Center" FontWeight="Bold" Foreground="#72D6A0"/><CheckBox Grid.Column="3" Name="AgentEnabled" Content="Агент включён"/>
         <Label Grid.Row="1" Content="Описание"/><TextBox Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="3" Name="AgentDescription"/>
         <Label Grid.Row="2" Content="Модель"/><ComboBox Grid.Row="2" Grid.Column="1" Name="AgentModel"/><Label Grid.Row="2" Grid.Column="2" Content="Режим"/><ComboBox Grid.Row="2" Grid.Column="3" Name="AgentMode"/>
        </Grid></Border>
        <TextBlock Name="AgentError" Foreground="#FF8585" TextWrapping="Wrap" Margin="9,0"/>
        <CheckBox Name="AgentDelegatable" Content="Team Lead может делегировать задачи этому агенту" Margin="10,5"/>
        <Expander Header="Полная инструкция агента" Foreground="#DDE4EE" Margin="4"><TextBox Name="AgentPrompt" AcceptsReturn="True" Height="145" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></Expander>
        <GroupBox Header="Skills"><Grid><Grid.RowDefinitions><RowDefinition Height="210"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><DataGrid Name="TeamSkillsGrid" AutoGenerateColumns="False" CanUserAddRows="False" Background="#15181E" Foreground="White" RowBackground="#20242C" AlternatingRowBackground="#262B34"><DataGrid.Columns><DataGridCheckBoxColumn Header="Назначен" Binding="{Binding IsAssigned}" Width="75"/><DataGridTextColumn Header="Skill" Binding="{Binding Id}" IsReadOnly="True" Width="190"/><DataGridTextColumn Header="Статус" Binding="{Binding Status}" IsReadOnly="True" Width="90"/><DataGridTextColumn Header="Описание" Binding="{Binding Description}" IsReadOnly="True" Width="*"/></DataGrid.Columns></DataGrid><Button Grid.Row="1" Name="OpenSelectedSkill" Content="Открыть выбранный SKILL.md" HorizontalAlignment="Left"/></Grid></GroupBox>
        <GroupBox Header="MCP-серверы"><Grid><Grid.RowDefinitions><RowDefinition Height="210"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><DataGrid Name="TeamMcpGrid" AutoGenerateColumns="False" CanUserAddRows="False" SelectionMode="Single" Background="#15181E" Foreground="White" RowBackground="#20242C" AlternatingRowBackground="#262B34"><DataGrid.Columns><DataGridCheckBoxColumn Header="Агенту" Binding="{Binding IsAssigned}" Width="65"/><DataGridCheckBoxColumn Header="Включён" Binding="{Binding IsEnabled}" Width="70"/><DataGridTextColumn Header="MCP" Binding="{Binding Id}" IsReadOnly="True" Width="125"/><DataGridTextColumn Header="Статус" Binding="{Binding Status}" IsReadOnly="True" Width="90"/><DataGridTextColumn Header="Назначение" Binding="{Binding Description}" IsReadOnly="True" Width="*"/><DataGridTextColumn Header="Executable" Binding="{Binding Command}" IsReadOnly="True" Width="150"/></DataGrid.Columns></DataGrid><StackPanel Grid.Row="1" Orientation="Horizontal"><Button Name="TestSelectedMcp" Content="Проверить MCP" Background="#176B52"/><Button Name="StopMcpCheck" Content="Остановить проверку" Background="#713A3A"/></StackPanel><TextBlock Grid.Row="2" Name="TeamMcpTestStatus" Text="Проверка MCP не запускалась" Foreground="#BFC9D7" TextWrapping="Wrap" Margin="8,2"/></Grid></GroupBox>
        <GroupBox Header="Разрешения и делегирование"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><TextBox Name="AgentPermissions" IsReadOnly="True" Height="115" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/><TextBox Grid.Column="1" Name="AgentDelegates" IsReadOnly="True" Height="115" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/></Grid></GroupBox>
       </StackPanel></ScrollViewer>
      </Grid>
      <DockPanel Grid.Row="2" Margin="3"><TextBlock Name="TeamStatus" Text="Просмотр не изменяет OpenCode." Foreground="#BFC9D7" VerticalAlignment="Center" TextWrapping="Wrap"/><StackPanel DockPanel.Dock="Right" Orientation="Horizontal"><Button Name="SaveAgent" Content="Сохранить изменения" Background="#176B52"/><Button Name="RestoreTeamConfig" Content="Восстановить предыдущую конфигурацию"/></StackPanel></DockPanel>
     </Grid>
    </TabItem>
    <TabItem Header="Telegram" Name="TelegramTab">
     <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel Margin="14" MaxWidth="900" HorizontalAlignment="Left">
      <Border Background="#18364A" BorderBrush="#3285B5" BorderThickness="1" CornerRadius="6" Padding="12" Margin="3"><StackPanel><TextBlock Text="BeeForge Telegram Bridge" FontSize="19" FontWeight="SemiBold" Foreground="White"/><TextBlock Name="TelegramStatus" Text="Проверка состояния..." Foreground="#A9D7F2" TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel></Border>
      <GroupBox Header="Подключение"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="175"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <CheckBox Grid.ColumnSpan="2" Name="TelegramEnabled" Content="Включить интеграцию и запускать мост вместе с BeeForge"/>
       <Label Grid.Row="1" Content="Bot token"/><StackPanel Grid.Row="1" Grid.Column="1"><PasswordBox Name="TelegramToken" Margin="5" Padding="7" Background="#20242C" Foreground="#F3F5F7" BorderBrush="#3A414D"/><TextBlock Name="TelegramTokenState" Text="Токен не сохранён" Foreground="#9EABC0" Margin="7,0"/></StackPanel>
       <Label Grid.Row="2" Content="Telegram User ID"/><TextBox Grid.Row="2" Grid.Column="1" Name="TelegramUserId"/>
       <Label Grid.Row="3" Content="Личный Chat ID"/><TextBox Grid.Row="3" Grid.Column="1" Name="TelegramChatId"/>
       <Label Grid.Row="4" Content="Автоматические сводки"/><TextBox Grid.Row="4" Grid.Column="1" Name="TelegramSummaryMinutes" Text="Отключены — используйте /status" IsReadOnly="True" Width="260" HorizontalAlignment="Left"/>
      </Grid></GroupBox>
       <GroupBox Header="Уведомления"><WrapPanel><CheckBox Name="TelegramNotifyDelegation" Content="Назначение агентов"/><CheckBox Name="TelegramNotifyCompletion" Content="Завершение этапов"/><CheckBox Name="TelegramNotifyErrors" Content="Ошибки и блокировки"/><CheckBox Name="TelegramPinnedStatus" Content="Закреплённый живой статус"/></WrapPanel></GroupBox>
       <GroupBox Header="Локальный голосовой ввод"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="175"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions><CheckBox Grid.ColumnSpan="2" Name="TelegramVoiceEnabled" Content="Распознавать голосовые локально (CPU, не занимает VRAM BeeLlama)"/><Label Grid.Row="1" Content="Модель faster-whisper"/><ComboBox Grid.Row="1" Grid.Column="1" Name="TelegramVoiceModel" Width="220" HorizontalAlignment="Left"><ComboBoxItem Content="tiny"/><ComboBoxItem Content="base"/><ComboBoxItem Content="small"/><ComboBoxItem Content="medium"/></ComboBox></Grid></GroupBox>
      <GroupBox Header="Разрешённые проекты"><Grid><Grid.RowDefinitions><RowDefinition Height="170"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><ListBox Name="TelegramProjects" Background="#111318" Foreground="White" BorderBrush="#343B46" ScrollViewer.HorizontalScrollBarVisibility="Disabled"><ListBox.ItemTemplate><DataTemplate><TextBlock Text="{Binding}" TextTrimming="CharacterEllipsis" ToolTip="{Binding}"/></DataTemplate></ListBox.ItemTemplate></ListBox><StackPanel Grid.Row="1" Orientation="Horizontal"><Button Name="TelegramAddProject" Content="Добавить папку"/><Button Name="TelegramRemoveProject" Content="Удалить выбранный"/></StackPanel></Grid></GroupBox>
      <Border Background="#302C20" BorderBrush="#8E7937" BorderThickness="1" CornerRadius="6" Padding="11" Margin="4"><TextBlock Text="Telegram получает названия проектов, статусы и краткие результаты. Reasoning, полные tool outputs, исходники, .env и полный diff не отправляются. Доступ разрешён только указанным User ID и личному Chat ID. Критические действия подтверждаются дважды." TextWrapping="Wrap" Foreground="#FFE4A3"/></Border>
      <WrapPanel Margin="2,8"><Button Name="TelegramSave" Content="Сохранить" Background="#176B52"/><Button Name="TelegramTest" Content="Проверить бота"/><Button Name="TelegramStart" Content="Запустить мост"/><Button Name="TelegramStop" Content="Остановить мост" Background="#713A3A"/><Button Name="TelegramOpenLog" Content="Открыть журнал"/></WrapPanel>
     </StackPanel></ScrollViewer>
    </TabItem>
    <TabItem Header="Тест" Name="TestTab">
     <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="14">
      <TextBlock Text="Тест производительности" FontSize="22" FontWeight="SemiBold" Foreground="White" Margin="4,0,4,10"/>
      <TextBlock Text="Benchmark отправляет детерминированный synthetic prompt через API и показывает фактическую скорость prefill и генерации. Thinking отключается только для тестового запроса." TextWrapping="Wrap" Foreground="#BFC9D7" Margin="4,0,4,12"/>
      <GroupBox Name="TestParametersGroup" Header="Параметры теста"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="155"/><ColumnDefinition Width="145"/><ColumnDefinition Width="155"/><ColumnDefinition Width="145"/><ColumnDefinition Width="155"/><ColumnDefinition Width="145"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
       <Label Content="Цель input tokens"/><ComboBox Grid.Column="1" Name="TestPromptTokens" IsEditable="True"/><Label Grid.Column="2" Content="Max output tokens"/><ComboBox Grid.Column="3" Name="TestOutputTokens" IsEditable="True"/><Label Grid.Column="4" Content="Timeout, секунд"/><TextBox Grid.Column="5" Name="TestTimeout" Text="900"/>
       <CheckBox Grid.Row="1" Grid.ColumnSpan="4" Name="ApplyBeforeTest" Content="Применить профиль и перезапустить сервер перед тестом" IsChecked="True"/><StackPanel Grid.Row="1" Grid.Column="4" Grid.ColumnSpan="2" Orientation="Horizontal"><Button Name="StartTest" Content="Тестировать" Background="#176B52"/><Button Name="StopTest" Content="Стоп тест" Background="#713A3A"/></StackPanel>
       <TextBlock Grid.Row="2" Grid.ColumnSpan="6" Name="TestLimitHint" Text="" Foreground="#FFBA69" Margin="8,4" TextWrapping="Wrap"/>
      </Grid></GroupBox>
      <Grid Margin="4,8"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
       <Border Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Состояние" Foreground="#98A4B5"/><TextBlock Name="TestState" Text="IDLE" FontSize="19" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="1" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Prompt / prefill" Foreground="#98A4B5"/><TextBlock Name="TestPromptTps" Text="— tok/s" FontSize="19" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="2" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Генерация" Foreground="#98A4B5"/><TextBlock Name="TestDecodeTps" Text="— tok/s" FontSize="19" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
       <Border Grid.Column="3" Background="#20242C" CornerRadius="6" Padding="12" Margin="4"><StackPanel><TextBlock Text="Время" Foreground="#98A4B5"/><TextBlock Name="TestElapsed" Text="— сек" FontSize="19" FontWeight="Bold" Foreground="White"/></StackPanel></Border>
      </Grid>
      <TextBlock Name="TestTokens" Text="Input: — | Output: —" Foreground="#C8D0DC" Margin="9,4"/>
      <TextBox Name="TestResult" IsReadOnly="True" Height="190" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" Text="Тест ещё не запускался."/>
      <TextBlock Text="«Стоп тест» завершает только отдельный benchmark-клиент. BeeLlama server и OpenCode продолжают работать." Foreground="#FFBA69" TextWrapping="Wrap" Margin="8"/>
     </StackPanel></ScrollViewer>
    </TabItem>
    <TabItem Header="Туториал">
     <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="18" MaxWidth="900" HorizontalAlignment="Left">
      <TextBlock Text="Как пользоваться BeeForge AI Console" FontSize="23" FontWeight="SemiBold" Foreground="White" Margin="0,0,0,14"/>
      <TextBlock Text="1. Выберите профиль" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="Слева выберите существующий профиль. «Новый» создаёт новую заготовку, а «Клон» копирует текущие параметры для экспериментов. Все профили равноправны; единственный профиль нельзя удалить, пока не создан другой." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="2. Выберите модель и runtime" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="На вкладке «Основные» выберите найденный GGUF или укажите файл через «Обзор». Runtime должен указывать на llama-server.exe. Кнопка «Модели» повторно сканирует каталоги LM Studio." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="3. Настройте context и память" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="Можно указать любое положительное значение context. Сохранять профиль для оценки не требуется: вкладка «Ресурсы» использует текущие поля формы и обновляется автоматически. Зелёный статус означает комфортный запас, жёлтый — работу близко к пределу, красный — вероятный spill/OOM. Для повседневной работы желательно оставить не менее 500–800 MiB." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="4. Производительность" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="Настройте KV, MTP и sampling для выбранной модели и подтвердите результат встроенным тестом. Reasoning budget задаёт жёсткий верхний предел внутреннего рассуждения, а качество reasoning выбирается в OpenCode." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="Vision: работа с изображениями" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="Для vision-модели включите «Изображения» и выберите mmproj*.gguf. Менеджер сначала ищет projector рядом с GGUF; файл должен соответствовать семейству модели. Projector увеличивает расход памяти примерно на свой размер, поэтому сначала посмотрите вкладку «Ресурсы». После успешного запуска и синхронизации OpenCode сможет прикреплять изображения только к этому vision-профилю." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="5. Сохранение и запуск" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="«Сохранить профиль» записывает настройки и при включённой галочке «Обновлять OpenCode» автоматически синхронизирует конфигурацию. Для нового vision-профиля image-capability включается после успешного запуска с projector. «Применить и перезапустить» сохраняет настройки, перезапускает сервер и ждёт /health." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="6. Мониторинг и остановка" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="«Открыть live log» показывает prompt/decode tok/s и ошибки в отдельном PowerShell. UI можно закрыть — модель продолжит работать. Для завершения сервера снова откройте менеджер и нажмите «Остановить»." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="7. Проверка производительности" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="На вкладке «Тест» задайте примерный размер input и max output. По умолчанию профиль автоматически применяется и сервер перезапускается, чтобы тестировать именно введённые параметры. Во время теста отображаются prefill/decode tok/s, токены и elapsed. «Стоп тест» отменяет benchmark, но не выключает модель." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="8. AI-команда OpenCode" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="Работайте через Team Lead: он определяет тип задачи и последовательно назначает специалистов. FAST применяется по умолчанию; STANDARD или RELEASE достаточно указать обычными словами в запросе. Основная команда — Team Lead, Software Engineer и объединённый Quality Engineer; остальные роли вызываются только по необходимости. Вкладка читает фактический opencode.json и показывает skills, MCP, разрешения и делегирование. Переключатель «Полный доступ» снимает системные запросы разрешений для всех агентов; при выключении прежние правила восстанавливаются." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="9. Telegram-управление" FontSize="17" FontWeight="Bold" Foreground="#74B9FF"/><TextBlock Text="Создайте личного бота через BotFather, укажите токен, собственные User ID и Chat ID, добавьте разрешённые проекты и проверьте соединение. Все новые задачи из Telegram всегда направляются Team Lead. Команда /fullaccess управляет полным доступом; включение требует двойного подтверждения. Остановка моста не останавливает BeeLlama или OpenCode." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
      <TextBlock Text="Если эксперимент не загрузился" FontSize="17" FontWeight="Bold" Foreground="#FFBA69"/><TextBlock Text="Откройте current.stderr.log или live log. OpenCode не изменяется при неудачном запуске. Исправьте параметры выбранного профиля либо запустите другой сохранённый профиль." TextWrapping="Wrap" Foreground="#D7DEE8" Margin="0,4,0,13"/>
     </StackPanel></ScrollViewer>
    </TabItem>
   </TabControl>
  </Grid>
  <WrapPanel Grid.Row="2" HorizontalAlignment="Center" Margin="0,9,0,5">
   <Button Name="SaveProfile" Content="Сохранить профиль"/><Button Name="ApplyRestart" Content="Применить и перезапустить" Background="#176B52"/><Button Name="StartServer" Content="Сохранить и запустить"/><Button Name="StopServer" Content="Остановить" Background="#713A3A"/><Button Name="OpenLiveLog" Content="Открыть live log"/><Button Name="OpenLogs" Content="Открыть папку logs"/>
  </WrapPanel>
  <Border Grid.Row="3" Background="#181B21" CornerRadius="5" Padding="9"><TextBlock Name="StatusLine" Text="Готово" TextWrapping="Wrap"/></Border>
 </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.Icon = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\beeforge-ai.ico'
function UI([string]$Name) { return $window.FindName($Name) }

$tooltips = [ordered]@{
    HeaderStatus='Текущее состояние управляемого BeeLlama server: readiness, PID и время работы.'
    ProfileList='Список сохранённых профилей. Выбор профиля загружает его параметры в форму.'
    NewProfile='Создать новую редактируемую заготовку профиля.'
    CloneProfile='Создать независимую копию выбранного профиля для экспериментов.'
    DeleteProfile='Удалить выбранный профиль. Единственный оставшийся профиль удалить нельзя.'
    ImportProfile='Импортировать профиль из JSON-файла.'
    ExportProfile='Сохранить выбранный профиль в отдельный JSON-файл.'
    RefreshModels='Повторно найти GGUF-модели и vision-projector файлы в каталогах LM Studio.'
    ProfileVisionGroup='Выбор модели, runtime, API alias и дополнительных компонентов для обработки изображений.'
    ProfileName='Отображаемое имя профиля внутри менеджера. На API-запросы не влияет.'
    ModelPath='Путь к основному GGUF-файлу языковой модели.'
    BrowseModel='Выбрать основной GGUF-файл через проводник.'
    ServerPath='Путь к llama-server.exe из нужной сборки BeeLlama.'
    BrowseRuntime='Выбрать llama-server.exe через проводник.'
    Alias='Имя модели в OpenAI-compatible API и OpenCode. Допустимы латинские буквы, цифры, точка, дефис и подчёркивание.'
    MmprojPath='Совместимый mmproj*.gguf для vision. Обычно должен находиться рядом с основной моделью и соответствовать её семейству.'
    BrowseMmproj='Выбрать vision-projector mmproj*.gguf через проводник.'
    VisionEnabled='Разрешить модели получать изображения. Требуется совместимый vision-projector.'
    VisionOffload='Загрузить vision-projector в VRAM. Это может ускорить обработку изображений, но уменьшает запас видеопамяти.'
    VisionHint='Результат проверки расположения projector и оценка дополнительного расхода RAM или VRAM.'
    ComputeGroup='Параметры контекста, GPU offload, пакетной обработки и CPU-потоков.'
    Context='Физический размер контекста сервера в токенах. Чем больше значение, тем больше KV cache и расход памяти.'
    GpuLayers='Сколько слоёв модели размещать на GPU. all — максимум; уменьшение переносит часть вычислений и весов в RAM и обычно снижает скорость.'
    Parallel='Число одновременных sequence slots. Значения выше 1 делят контекст и увеличивают расход памяти; для одного агента обычно используется 1.'
    Batch='Максимальный logical batch для обработки prompt. Большее значение может ускорить prefill, но требует больше памяти.'
    Ubatch='Физический micro-batch вычислений. Не должен превышать Batch; увеличение может ускорить prefill ценой VRAM.'
    FlashAttention='Использовать Flash Attention. Обычно ускоряет длинный контекст и уменьшает расход памяти, если runtime и GPU поддерживают его.'
    Threads='Число CPU-потоков при генерации и операциях, выполняемых на CPU.'
    ThreadsBatch='Число CPU-потоков для пакетной обработки prompt.'
    CacheReuse='Минимальный объём совпавшего префикса для повторного использования prompt cache. Для multimodal runtime может отключить эту функцию.'
    ApiGroup='Сетевой адрес BeeLlama и параметры интеграции с OpenCode.'
    Host='Адрес прослушивания API. 127.0.0.1 оставляет сервер доступным только на этом ПК.'
    Port='TCP-порт OpenAI-compatible API. Он должен быть свободен перед запуском.'
    OpenCodeSync='Автоматически обновлять alias, endpoint, context и возможности модели в конфигурации OpenCode при сохранении.'
    OpenCodeOutput='Максимум output tokens, который OpenCode считает доступным. Он должен быть меньше физического context.'
    KvGroup='Формат KV cache определяет расход памяти, скорость и точность сохранения длинного контекста.'
    KvK='Тип квантования K-cache. Меньшая разрядность экономит VRAM, но может ухудшить качество.'
    KvV='Тип квантования V-cache. Меньшая разрядность экономит VRAM, но может сильнее влиять на качество ответа.'
    KvTailTokens='Число последних токенов KV cache, которые хранятся в отдельном, обычно более точном формате.'
    KvTailType='Формат хранения последних KV tokens. F16/BF16 точнее, но занимают больше памяти.'
    ReasoningGroup='Управление reasoning на сервере. Уровень Default/Low/Medium/High выбирается отдельно в OpenCode.'
    ReasoningEnabled='Разрешить модели формировать внутреннее рассуждение и reasoning_content.'
    ReasoningBudget='Жёсткий верхний предел reasoning tokens. Это защита от бесконтрольного длинного рассуждения, а не выбор уровня качества.'
    ReasoningPreserve='Сохранять reasoning_content в истории запроса, если это поддерживается моделью и клиентом.'
    MtpGroup='Speculative decoding с нативной MTP-головой модели. Эффект по скорости зависит от конкретной модели и требует A/B-теста.'
    MtpEnabled='Включить native MTP speculative decoding, если выбранная модель и runtime его поддерживают.'
    MtpNMax='Максимальное число speculative tokens за шаг. Большее значение не гарантирует ускорение и может увеличить расход памяти.'
    SamplingGroup='Параметры случайности и отбора следующего токена.'
    Temperature='Случайность генерации. Меньше — стабильнее и предсказуемее; больше — разнообразнее.'
    TopP='Nucleus sampling: модель выбирает из токенов с суммарной вероятностью до этого порога.'
    TopK='Ограничивает выбор K наиболее вероятными токенами. 0 обычно отключает ограничение.'
    MinP='Отбрасывает токены с вероятностью слишком малой относительно лучшего кандидата.'
    RepeatPenalty='Штраф за повторение уже использованных токенов. 1.0 означает отсутствие штрафа.'
    ResourceBreakdownGroup='Расчётные составляющие VRAM. Это прогноз; окончательное значение определяется только реальным запуском.'
    EstimateModelSize='Размер выбранного GGUF-файла на диске.'
    EstimateVram='Прогноз общей dedicated VRAM для текущих параметров.'
    EstimateHeadroom='Прогноз свободной VRAM после загрузки. Для стабильной работы полезно оставлять практический запас.'
    EstimateSpill='Оценка весов и projector, размещаемых в системной RAM из-за выбранного GPU offload.'
    ActualVram='Текущее использование dedicated VRAM по данным GPU. Это общесистемный показатель.'
    ActualRam='Текущее использование физической RAM всей системой.'
    ResourceWeights='Оценка VRAM, занятой весами модели с учётом GPU layers.'
    ResourceKv='Оценка VRAM для KV cache с учётом context и типов K/V.'
    ResourceBuffers='Оценка служебных буферов runtime, batch, parallel, MTP и vision.'
    ResourceBackground='Оценка VRAM, уже занятой системой и другими приложениями.'
    RefreshEstimate='Немедленно пересчитать прогноз ресурсов из текущих значений формы.'
    AdvancedGrid='Дополнительные аргументы llama-server в виде безопасных пар флаг/значение. Управляемые интерфейсом флаги дублировать нельзя.'
    AddAdvanced='Добавить строку дополнительного аргумента.'
    RemoveAdvanced='Удалить выбранную строку дополнительного аргумента.'
    CommandPreview='Предварительный просмотр полной команды запуска. Поле доступно только для чтения.'
    TeamAgentList='Фактические агенты из opencode.json. PRIMARY — основной агент, ACTIVE — доступный специалист, DISABLED — отключён.'
    NewAgent='Создать нового безопасного специалиста с запретом делегирования по умолчанию.'
    CloneAgent='Создать независимую копию выбранного агента вместе с его инструкцией и разрешениями.'
    DeleteAgent='Удалить выбранного пользовательского агента. Последний primary и встроенный build защищены.'
    RefreshTeam='Повторно прочитать конфигурацию OpenCode, каталог skills и состояние MCP.'
    OpenTeamConfig='Открыть фактический opencode.json. Секреты и значения переменных окружения в BeeForge не отображаются.'
    AgentId='Стабильный идентификатор агента в opencode.json. После создания не переименовывается.'
    AgentStatusBadge='Результат валидации выбранного агента: PRIMARY, ACTIVE, DISABLED или CONFIG ERROR.'
    AgentDescription='Описание роли, которое OpenCode показывает при выборе и делегировании агента.'
    AgentModel='Модель OpenCode для этого агента. Список формируется из provider.beellama.models.'
    AgentMode='primary — основной режим; subagent — только делегируемый специалист; all — доступен в обоих сценариях.'
    AgentEnabled='Снимает или устанавливает disable для выбранного агента.'
    AgentDelegatable='Добавляет агента в разрешённые назначения task для Team Lead.'
    AgentPrompt='Полная системная инструкция агента. Скрыта по умолчанию; изменения применяются только после сохранения.'
    TeamSkillsGrid='Доступные и назначенные skills. Повреждённые каталоги отмечены INVALID и не могут быть назначены.'
    OpenSelectedSkill='Открыть выбранный SKILL.md для просмотра в стандартном текстовом редакторе.'
    TeamMcpGrid='MCP из opencode.json: «Агенту» выдаёт доступ выбранному агенту, «Включён» управляет глобальным enabled.'
    TestSelectedMcp='Выполнить ограниченный MCP initialize-тест. Для Docker проверяется доступность Docker Engine без запуска контейнера.'
    StopMcpCheck='Остановить только процесс диагностического MCP-теста и его дочерние процессы.'
    TeamMcpTestStatus='Результат последней ограниченной проверки MCP initialize; секреты окружения здесь не выводятся.'
    AgentPermissions='Сводка собственных разрешений агента. Редактор сохраняет существующие правила, не расширяя их автоматически.'
    AgentDelegates='Список специалистов, которым выбранный агент может делегировать задачи.'
    SaveAgent='Проверить и атомарно сохранить агента, skills, MCP и делегирование. Перед изменением создаётся ограниченная резервная копия.'
    RestoreTeamConfig='Восстановить последнюю резервную копию, созданную редактором AI-команды.'
    TestParametersGroup='Настройки конечного synthetic benchmark через OpenAI-compatible API.'
    TestPromptTokens='Желаемое число входных токенов synthetic prompt. Менеджер ограничит его доступным контекстом.'
    TestOutputTokens='Максимальное число токенов генерации в benchmark.'
    TestTimeout='Максимальная длительность тестового клиента в секундах, после которой тест будет остановлен.'
    ApplyBeforeTest='Перед тестом сохранить профиль, перезапустить BeeLlama и дождаться готовности, чтобы измерять именно текущие параметры формы.'
    StartTest='Запустить контролируемый benchmark и показывать prefill/decode tok/s.'
    StopTest='Остановить только benchmark-клиент. BeeLlama server продолжит работать.'
    TestState='Текущее состояние benchmark: запуск, выполнение, завершение, ошибка или остановка.'
    TestPromptTps='Фактическая средняя скорость обработки входного prompt в токенах в секунду.'
    TestDecodeTps='Фактическая средняя скорость генерации output tokens в секунду.'
    TestElapsed='Полное wall-clock время benchmark.'
    TestResult='Подробный результат последнего теста: токены, скорости, время и причина завершения.'
    SaveProfile='Проверить и сохранить параметры. При включённой синхронизации автоматически обновляет OpenCode.'
    ApplyRestart='Сохранить профиль, остановить управляемый сервер, запустить его с новыми параметрами и дождаться /health.'
    StartServer='Сохранить текущую форму и запустить выбранный профиль.'
    StopServer='Остановить только llama-server.exe, PID которого записан менеджером.'
    OpenLiveLog='Открыть отдельное окно с prompt/decode tok/s и ошибками текущего сервера в реальном времени.'
    OpenLogs='Открыть папку текущих runtime-логов в проводнике.'
    StatusLine='Последнее действие менеджера, ошибка или краткие метрики текущего сервера.'
}
foreach ($entry in $tooltips.GetEnumerator()) {
    $control = UI $entry.Key
    if ($control) {
        # A plain string inside ToolTip uses a ContentPresenter and does not wrap,
        # so long Russian descriptions can be clipped at a screen/window edge.
        $tipText = New-Object System.Windows.Controls.TextBlock
        $tipText.Text = [string]$entry.Value
        $tipText.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tipText.MaxWidth = 400
        $tipText.LineHeight = 19
        $tip = New-Object System.Windows.Controls.ToolTip
        $tip.Content = $tipText
        $tip.MaxWidth = 430
        $control.ToolTip = $tip
        [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($control,350)
        [System.Windows.Controls.ToolTipService]::SetShowDuration($control,30000)
        [System.Windows.Controls.ToolTipService]::SetBetweenShowDelay($control,100)
    }
}

$store = $null
$currentProfile = $null
$pendingBenchmark = $null
$teamSnapshot = $null
$currentTeamAgent = $null
$teamRefreshInProgress = $false
$lastMcpTestSignature = ''
$advanced = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$teamSkills = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$teamMcps = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
$telegramProjects = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
(UI 'AdvancedGrid').ItemsSource = $advanced
(UI 'TeamSkillsGrid').ItemsSource = $teamSkills
(UI 'TeamMcpGrid').ItemsSource = $teamMcps
(UI 'TelegramProjects').ItemsSource = $telegramProjects
(UI 'AgentMode').ItemsSource = @('primary','subagent','all')

foreach ($name in @('KvK','KvV')) { (UI $name).ItemsSource = @('f16','bf16','q8_0','q4_0','iq4_nl','kvarn4','kvarn3') }
(UI 'KvTailType').ItemsSource = @('f16','bf16','q8_0','q4_0')
(UI 'MtpNMax').ItemsSource = @(2,3,4)
(UI 'GpuLayers').ItemsSource = @('all') + @(64..0 | ForEach-Object { [string]$_ })
(UI 'TestPromptTokens').ItemsSource = @(1024,4096,8192,16384,32768)
(UI 'TestPromptTokens').Text = '4096'
(UI 'TestOutputTokens').ItemsSource = @(64,128,256,512,1024)
(UI 'TestOutputTokens').Text = '256'

$resourceDebounce = New-Object Windows.Threading.DispatcherTimer
$resourceDebounce.Interval = [TimeSpan]::FromMilliseconds(450)
$resourceDebounce.Add_Tick({ $resourceDebounce.Stop(); Update-ResourceEstimate })
function Queue-ResourceEstimate { $resourceDebounce.Stop(); $resourceDebounce.Start() }

function Show-Message([string]$Text, [string]$Title='BeeForge AI Console', [Windows.MessageBoxImage]$Icon=[Windows.MessageBoxImage]::Information) {
    [Windows.MessageBox]::Show($window,$Text,$Title,[Windows.MessageBoxButton]::OK,$Icon) | Out-Null
}

function Refresh-ModelList {
    try {
        $current = (UI 'ModelPath').Text
        (UI 'ModelPath').ItemsSource = @(Get-BeeModelFiles)
        (UI 'ModelPath').Text = $current
        (UI 'StatusLine').Text = "Найдено GGUF: $(@((UI 'ModelPath').ItemsSource).Count)"
    } catch { Show-Message $_.Exception.Message 'Ошибка поиска моделей' Error }
}

function Refresh-VisionProjectorList([switch]$PreferDetected) {
    try {
        $modelPath = (UI 'ModelPath').Text.Trim()
        $current = (UI 'MmprojPath').Text.Trim()
        $items = @(Get-BeeVisionProjectorFiles $modelPath)
        (UI 'MmprojPath').ItemsSource = $items
        if ($PreferDetected -and $items.Count -gt 0) { $current = $items[0] }
        (UI 'MmprojPath').Text = $current
        Update-VisionHint
    } catch { (UI 'VisionHint').Text = "Не удалось найти projector: $($_.Exception.Message)" }
}

function Update-VisionHint {
    $enabled = [bool](UI 'VisionEnabled').IsChecked
    $offload = [bool](UI 'VisionOffload').IsChecked
    $modelPath = (UI 'ModelPath').Text.Trim()
    $mmprojPath = (UI 'MmprojPath').Text.Trim()
    if (-not $enabled) { (UI 'VisionHint').Foreground='#98A4B5'; (UI 'VisionHint').Text='Выключено: OpenCode будет работать только с текстом'; return }
    if ([string]::IsNullOrWhiteSpace($mmprojPath)) { (UI 'VisionHint').Foreground='#FFBA69'; (UI 'VisionHint').Text='Выберите mmproj*.gguf — запуск будет заблокирован до выбора'; return }
    if (-not (Test-Path -LiteralPath $mmprojPath -PathType Leaf)) { (UI 'VisionHint').Foreground='#FF7B7B'; (UI 'VisionHint').Text='Projector-файл не найден'; return }
    $sameFolder = ((Split-Path -Parent $modelPath) -eq (Split-Path -Parent $mmprojPath))
    $sizeMiB = (Get-Item -LiteralPath $mmprojPath).Length / 1MB
    (UI 'VisionHint').Foreground = if ($sameFolder) { '#79D6A3' } else { '#FFBA69' }
    $placement = if ($offload) { "GPU: +$([math]::Round($sizeMiB)) MiB VRAM" } else { "RAM: +$([math]::Round($sizeMiB)) MiB (рекомендуется)" }
    (UI 'VisionHint').Text = if ($sameFolder) { "Найден рядом с моделью; $placement" } else { "Вне папки модели: проверьте совместимость; $placement" }
}

function Refresh-ProfileList([string]$SelectId) {
    $script:store = Get-BeeProfileStore
    (UI 'ProfileList').ItemsSource = $null
    (UI 'ProfileList').ItemsSource = @($script:store.profiles)
    $target = @($script:store.profiles | Where-Object { $_.id -eq $SelectId }) | Select-Object -First 1
    if (-not $target) { $target = @($script:store.profiles)[0] }
    (UI 'ProfileList').SelectedItem = $target
}

function Load-Profile($Profile) {
    if (-not $Profile) { return }
    $script:currentProfile = $Profile
    $map = @{
        ProfileName='name'; ModelPath='modelPath'; ServerPath='serverPath'; Alias='alias'; Context='context'; Parallel='parallel'; Batch='batch'; Ubatch='ubatch'; Threads='threads'; ThreadsBatch='threadsBatch'; CacheReuse='cacheReuse'; Host='host'; Port='port'; OpenCodeOutput='openCodeOutput'; KvTailTokens='kvTailTokens'; ReasoningBudget='reasoningBudget'; Temperature='temperature'; TopP='topP'; TopK='topK'; MinP='minP'; RepeatPenalty='repeatPenalty'
    }
    foreach ($control in $map.Keys) { (UI $control).Text = [string]$Profile.($map[$control]) }
    (UI 'VisionEnabled').IsChecked = [bool]($Profile.PSObject.Properties['visionEnabled'] -and $Profile.visionEnabled)
    (UI 'VisionOffload').IsChecked = [bool]($Profile.PSObject.Properties['visionOffload'] -and $Profile.visionOffload)
    (UI 'MmprojPath').Text = if ($Profile.PSObject.Properties['mmprojPath']) { [string]$Profile.mmprojPath } else { '' }
    Refresh-VisionProjectorList
    (UI 'GpuLayers').SelectedItem = [string]$Profile.gpuLayers
    foreach ($pair in @(@('FlashAttention','flashAttention'),@('OpenCodeSync','openCodeSync'),@('ReasoningEnabled','reasoningEnabled'),@('ReasoningPreserve','reasoningPreserve'),@('MtpEnabled','mtpEnabled'))) { (UI $pair[0]).IsChecked = [bool]$Profile.($pair[1]) }
    foreach ($pair in @(@('KvK','kvK'),@('KvV','kvV'),@('KvTailType','kvTailType'),@('MtpNMax','mtpNMax'))) { (UI $pair[0]).SelectedItem = $Profile.($pair[1]) }
    $advanced.Clear()
    foreach ($item in @($Profile.advancedArgs)) { $advanced.Add([pscustomobject]@{ flag=[string]$item.flag; value=[string]$item.value }) }
    Update-Preview
    Update-VisionHint
    Update-ResourceEstimate
    Update-TestLimitHint
}

function Get-FormProfile {
    if (-not $script:currentProfile) { throw 'Профиль не выбран' }
    $p = ($script:currentProfile | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
    foreach ($field in @('visionEnabled','visionOffload','mmprojPath')) {
        if (-not $p.PSObject.Properties[$field]) {
            $defaultValue = if ($field -eq 'mmprojPath') { '' } else { $false }
            $p | Add-Member -NotePropertyName $field -NotePropertyValue $defaultValue
        }
    }
    $p.name=(UI 'ProfileName').Text.Trim(); $p.modelPath=(UI 'ModelPath').Text.Trim(); $p.serverPath=(UI 'ServerPath').Text.Trim(); $p.alias=(UI 'Alias').Text.Trim()
    $p.context=[int](UI 'Context').Text; $p.gpuLayers=(UI 'GpuLayers').Text.Trim(); $p.parallel=[int](UI 'Parallel').Text; $p.batch=[int](UI 'Batch').Text; $p.ubatch=[int](UI 'Ubatch').Text; $p.threads=[int](UI 'Threads').Text; $p.threadsBatch=[int](UI 'ThreadsBatch').Text; $p.cacheReuse=[int](UI 'CacheReuse').Text
    $p.flashAttention=[bool](UI 'FlashAttention').IsChecked; $p.host=(UI 'Host').Text.Trim(); $p.port=[int](UI 'Port').Text; $p.openCodeSync=[bool](UI 'OpenCodeSync').IsChecked; $p.openCodeOutput=[int](UI 'OpenCodeOutput').Text
    $p.visionEnabled=[bool](UI 'VisionEnabled').IsChecked; $p.visionOffload=[bool](UI 'VisionOffload').IsChecked; $p.mmprojPath=(UI 'MmprojPath').Text.Trim()
    $p.kvK=[string](UI 'KvK').SelectedItem; $p.kvV=[string](UI 'KvV').SelectedItem; $p.kvTailTokens=[int](UI 'KvTailTokens').Text; $p.kvTailType=[string](UI 'KvTailType').SelectedItem
    $p.reasoningEnabled=[bool](UI 'ReasoningEnabled').IsChecked; $p.reasoningBudget=[int](UI 'ReasoningBudget').Text; $p.reasoningPreserve=[bool](UI 'ReasoningPreserve').IsChecked; $p.mtpEnabled=[bool](UI 'MtpEnabled').IsChecked; $p.mtpNMax=[int](UI 'MtpNMax').SelectedItem
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $p.temperature=[double]::Parse((UI 'Temperature').Text.Replace(',','.'),$culture); $p.topP=[double]::Parse((UI 'TopP').Text.Replace(',','.'),$culture); $p.topK=[int](UI 'TopK').Text; $p.minP=[double]::Parse((UI 'MinP').Text.Replace(',','.'),$culture); $p.repeatPenalty=[double]::Parse((UI 'RepeatPenalty').Text.Replace(',','.'),$culture)
    $p.advancedArgs = @($advanced | ForEach-Object { [pscustomobject]@{flag=[string]$_.flag;value=[string]$_.value} })
    return $p
}

function Update-Preview {
    try { (UI 'CommandPreview').Text = Get-BeeCommandPreview (Get-FormProfile) } catch { (UI 'CommandPreview').Text = "Заполните корректные значения: $($_.Exception.Message)" }
}

function Get-KvMemoryFactor([string]$Type) {
    switch ($Type.ToLowerInvariant()) {
        'f16' { return 4.0 }; 'bf16' { return 4.0 }; 'q8_0' { return 2.0 }
        'kvarn3' { return 0.75 }
        default { return 1.0 }
    }
}

function Update-ResourceEstimate {
    try {
        $p = Get-FormProfile
        if (-not (Test-Path -LiteralPath $p.modelPath -PathType Leaf)) { throw 'Сначала выберите существующий GGUF-файл' }
        $modelMiB = (Get-Item -LiteralPath $p.modelPath).Length / 1MB
        $visionMiB = 0.0
        if ([bool]$p.visionEnabled -and -not [string]::IsNullOrWhiteSpace([string]$p.mmprojPath) -and (Test-Path -LiteralPath $p.mmprojPath -PathType Leaf)) {
            $visionMiB = (Get-Item -LiteralPath $p.mmprojPath).Length / 1MB
        }
        $visionGpuMiB = if ([bool]$p.visionOffload) { $visionMiB } else { 0.0 }
        $visionRamMiB = if ([bool]$p.visionOffload) { 0.0 } else { $visionMiB }
        $status = Get-BeeServerStatus
        $gpuTotalMiB = if ($status.VramTotalMiB) { [double]$status.VramTotalMiB } else { 16303.0 }

        $gpuFraction = 1.0
        $layerNote = 'все слои на GPU'
        if ([string]$p.gpuLayers -ne 'all') {
            $layerCount = 0
            if (-not [int]::TryParse([string]$p.gpuLayers,[ref]$layerCount)) { throw 'GPU layers должен быть all или целым числом' }
            $gpuFraction = [math]::Max(0.0,[math]::Min(1.0,$layerCount / 64.0))
            $layerNote = "примерно $([math]::Round($gpuFraction*100))% весов на GPU (для прогноза принято 64 слоя)"
        }

        $context = [double]$p.context
        $tail = [math]::Min([double]$p.kvTailTokens,$context)
        $mainFactor = ((Get-KvMemoryFactor ([string]$p.kvK)) + (Get-KvMemoryFactor ([string]$p.kvV))) / 2.0
        $tailFactor = Get-KvMemoryFactor ([string]$p.kvTailType)
        $effectiveKvFactor = if ($context -gt 0) { ((($context-$tail)*$mainFactor)+($tail*$tailFactor))/$context } else { 1.0 }
        $kvMiB = 2306.0 * ($context / 162000.0) * $effectiveKvFactor
        $weightVramMiB = $modelMiB * 1.02 * $gpuFraction
        $bufferScale = [math]::Sqrt(([math]::Max(1,[double]$p.batch)/2048.0) * ([math]::Max(1,[double]$p.ubatch)/512.0))
        $buffersMiB = 350.0 * $bufferScale + (50.0 * [math]::Max(0,[int]$p.parallel-1)) + $visionGpuMiB
        if (-not [bool]$p.flashAttention) { $buffersMiB += 250.0 }
        if ([bool]$p.mtpEnabled) { $buffersMiB += 350.0 }
        $idleMiB = if (-not $status.Running -and $status.VramUsedMiB) { [math]::Max(760.0,[double]$status.VramUsedMiB) } else { 760.0 }
        $estimateMiB = $idleMiB + $weightVramMiB + $kvMiB + $buffersMiB
        $headroomMiB = $gpuTotalMiB - $estimateMiB
        $ramSpillMiB = $modelMiB * (1.0-$gpuFraction) * 1.05 + $visionRamMiB
        $riskHeadroomMiB = $headroomMiB
        $measurementNote = ''
        if ($status.Running -and [int]$status.Context -eq [int]$p.context -and $status.Model -eq [IO.Path]::GetFileName($p.modelPath) -and $status.VramUsedMiB) {
            $actualHeadroomMiB = [double]$status.VramTotalMiB - [double]$status.VramUsedMiB
            $riskHeadroomMiB = [math]::Min($riskHeadroomMiB,$actualHeadroomMiB)
            $measurementNote = " Фактический запас текущего запуска: $([math]::Round($actualHeadroomMiB)) MiB."
        }

        (UI 'EstimateModelSize').Text = ('{0:N2} GiB' -f ($modelMiB/1024.0))
        (UI 'EstimateVram').Text = ('{0:N2} GiB' -f ($estimateMiB/1024.0))
        (UI 'EstimateHeadroom').Text = ('{0:N0} MiB' -f $headroomMiB)
        (UI 'EstimateSpill').Text = ('{0:N2} GiB' -f ($ramSpillMiB/1024.0))
        (UI 'ActualVram').Text = if ($status.VramUsedMiB) { '{0:N2} / {1:N2} GiB' -f ($status.VramUsedMiB/1024.0),($status.VramTotalMiB/1024.0) } else { 'н/д' }
        (UI 'ActualRam').Text = if ($status.RamUsedGiB) { '{0:N1} / {1:N1} GiB' -f $status.RamUsedGiB,$status.RamTotalGiB } else { 'н/д' }
        (UI 'ResourceWeights').Text = ('{0:N2} GiB' -f ($weightVramMiB/1024.0))
        (UI 'ResourceKv').Text = ('{0:N0} MiB' -f $kvMiB)
        (UI 'ResourceBuffers').Text = ('{0:N0} MiB' -f $buffersMiB)
        (UI 'ResourceBackground').Text = ('{0:N0} MiB' -f $idleMiB)
        (UI 'ResourceCalculatedFrom').Text = "Рассчитано $(Get-Date -Format 'HH:mm:ss') из формы: ctx $([int]$p.context) | KV $($p.kvK)/$($p.kvV) | tail $($p.kvTailTokens) $($p.kvTailType) | GPU layers $($p.gpuLayers)"

        $baselineContext = 162000.0
        $baselineTail = [math]::Min([double]$p.kvTailTokens,$baselineContext)
        $baselineEffective = ((($baselineContext-$baselineTail)*$mainFactor)+($baselineTail*$tailFactor))/$baselineContext
        $baselineKvMiB = 2306.0 * $baselineEffective
        $contextSavingMiB = $baselineKvMiB - $kvMiB
        $kvComparison = if ($p.kvK -eq 'q4_0' -and $p.kvV -eq 'q4_0') { 'q4_0/q4_0 и KVarN4/KVarN4 оцениваются почти одинаково: оба хранят KV примерно в 4 битах.' } else { "Коэффициент KV относительно KVarN4/KVarN4: $('{0:N2}'-f$mainFactor)x." }
        $visionImpact = if ([bool]$p.visionEnabled) { if ($visionMiB -gt 0) { if ([bool]$p.visionOffload) { "Vision projector добавляет примерно $('{0:N0}' -f $visionGpuMiB) MiB к VRAM." } else { "Vision projector остаётся в RAM: примерно $('{0:N0}' -f $visionRamMiB) MiB; VRAM сохраняется для контекста." } } else { 'Vision включён, но projector пока не выбран или не найден.' } } else { 'Vision выключен.' }
        (UI 'ResourceImpact').Text = "Что изменилось: context $([int]$p.context) уменьшает KV примерно на $('{0:N0}'-f[math]::Max(0,$contextSavingMiB)) MiB относительно 162K при тех же KV-настройках. $kvComparison $visionImpact Главный потребитель здесь — веса выбранной модели ($('{0:N2}'-f($weightVramMiB/1024.0)) GiB). Итоговые параметры следует проверять тестом именно для этой модели."

        $targetHeadroomMiB = 800.0
        $fullWeightMiB = $modelMiB*1.02
        $availableForWeights = $gpuTotalMiB-$targetHeadroomMiB-$idleMiB-$kvMiB-$buffersMiB
        $recommendedFraction = [math]::Max(0.0,[math]::Min(1.0,$availableForWeights/$fullWeightMiB))
        $recommendedLayers = [math]::Floor($recommendedFraction*64.0)
        $recommendedRamMiB = $modelMiB*(1.0-$recommendedFraction)*1.05
        if ($recommendedFraction -ge 0.995) { (UI 'ResourceRecommendation').Text='Рекомендация: все GPU layers должны помещаться с целевым запасом около 800 MiB.' }
        else { (UI 'ResourceRecommendation').Text="Рекомендация для запаса около 800 MiB: начните примерно с GPU layers = $recommendedLayers из условных 64. Около $('{0:N2}'-f($recommendedRamMiB/1024.0)) GiB весов перейдёт в RAM. Точное число слоёв подтвердите реальным запуском." }

        $card = UI 'ResourceRiskCard'
        if ($riskHeadroomMiB -ge 1200) { $card.Background='#213A2B';$card.BorderBrush='#3EA66B';$verdict="Хороший запас: ожидается полное размещение в VRAM, запас около $([math]::Round($headroomMiB)) MiB." }
        elseif ($riskHeadroomMiB -ge 500) { $card.Background='#394024';$card.BorderBrush='#A6A63E';$verdict="Допустимо, но близко к пределу: расчётный запас около $([math]::Round($headroomMiB)) MiB. Проверьте реальный peak VRAM." }
        elseif ($riskHeadroomMiB -ge 0) { $card.Background='#49351F';$card.BorderBrush='#D58A36';$verdict="Высокий риск: практический запас меньше 500 MiB. Возможен Shared GPU Memory spill или OOM." }
        else { $card.Background='#4A2428';$card.BorderBrush='#D85862';$verdict="Не помещается по оценке: превышение VRAM примерно на $([math]::Round(-$headroomMiB)) MiB. Уменьшите context/GPU layers или KV." }
        (UI 'ResourceVerdict').Text = $verdict + $measurementNote
        (UI 'ResourceDetails').Text = "Модель: $([IO.Path]::GetFileName($p.modelPath))`nРаскладка: $layerNote`nФактический Shared GPU Memory через nvidia-smi на Windows надёжно не доступен; отрицательный или очень малый запас помечается как риск spill. Прогноз откалиброван по рабочему Qwen38 162K KVarN4/KVarN4 (факт около 15.7 GiB)."
    } catch {
        (UI 'ResourceVerdict').Text = "Не удалось рассчитать: $($_.Exception.Message)"
        (UI 'ResourceRiskCard').Background='#4A2428'; (UI 'ResourceRiskCard').BorderBrush='#D85862'
    }
}

function Confirm-Warnings($Validation) {
    if ($Validation.Warnings.Count -eq 0) { return $true }
    return ([Windows.MessageBox]::Show($window,($Validation.Warnings -join "`n") + "`n`nПродолжить?",'Предупреждение',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning) -eq [Windows.MessageBoxResult]::Yes)
}

function Save-CurrentProfile([switch]$Quiet) {
    $p = Get-FormProfile
    if ([string]::IsNullOrWhiteSpace($p.name)) { throw 'Введите имя профиля' }
    $validation = Test-BeeProfile $p
    if (-not $validation.Valid) { throw ($validation.Errors -join "`n") }
    if (-not $Quiet -and -not (Confirm-Warnings $validation)) { return $null }
    $script:store = Get-BeeProfileStore
    $profiles = @()
    $found = $false
    foreach ($item in @($script:store.profiles)) { if ($item.id -eq $p.id) { $profiles += $p; $found=$true } else { $profiles += $item } }
    if (-not $found) { $profiles += $p }
    $script:store.profiles = $profiles
    Save-BeeProfileStore $script:store
    $script:currentProfile = $p
    Refresh-ProfileList $p.id
    if ([bool]$p.openCodeSync) {
        $runningMatch = Test-BeeRunningProfileMatch $p
        if ([bool]$p.visionEnabled -and -not $runningMatch) {
            (UI 'StatusLine').Text = "Vision-профиль сохранён. OpenCode останется text-only до успешного запуска с projector; нажмите «Применить и перезапустить»."
        } else {
            Update-BeeOpenCode $p | Out-Null
            if ($runningMatch) {
            (UI 'StatusLine').Text = "Профиль сохранён и OpenCode синхронизирован: beellama/$($p.alias)"
            } else {
            (UI 'StatusLine').Text = "Профиль и OpenCode сохранены. Нажмите «Применить и перезапустить»: сейчас сервер обслуживает другой профиль."
            }
        }
    } else { (UI 'StatusLine').Text = "Профиль сохранён: $($p.name); синхронизация OpenCode отключена" }
    return $p
}

function Start-SelectedProfile([bool]$SaveFirst) {
    try {
        $p = if ($SaveFirst) { Save-CurrentProfile } else { Get-BeeProfile $script:currentProfile.id }
        if (-not $p) { return }
        if (-not $SaveFirst) { $v=Test-BeeProfile $p; if(-not $v.Valid){throw($v.Errors -join "`n")}; if(-not (Confirm-Warnings $v)){return} }
        (UI 'StatusLine').Text = "Запуск $($p.name): проверка runtime и ожидание /health до 120 секунд..."
        $manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\server-manager.ps1'
        $line = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Start -ProfileId "{1}"' -f $manager,$p.id
        Start-Process -FilePath 'powershell.exe' -ArgumentList $line -WindowStyle Hidden | Out-Null
    } catch { Show-Message $_.Exception.Message 'Запуск невозможен' Error }
}

function Get-SafeTestInput([int]$Context,[int]$OutputTokens) {
    $available = $Context - $OutputTokens - 256
    if ($available -lt 256) { return 0 }
    return [int]([math]::Floor($available/256.0)*256.0)
}

function Update-TestLimitHint {
    try {
        $contextValue=[int](UI 'Context').Text
        $outputValue=[int](UI 'TestOutputTokens').Text
        $safe=Get-SafeTestInput $contextValue $outputValue
        if($safe-lt 256){(UI 'TestLimitHint').Text="Context $contextValue слишком мал для output $outputValue и служебного запаса."}
        else{(UI 'TestLimitHint').Text="Context: $contextValue | безопасный максимум фактического input: примерно $safe tokens. Если выбрано больше, input будет уменьшен автоматически."}
    } catch { (UI 'TestLimitHint').Text='Введите корректные целые context и output.' }
}

function Begin-Benchmark {
    try {
        $promptTokens = [int](UI 'TestPromptTokens').Text
        $outputTokens = [int](UI 'TestOutputTokens').Text
        $timeout = [int](UI 'TestTimeout').Text
        $applyProfile=[bool](UI 'ApplyBeforeTest').IsChecked
        $profileForLimit=if($applyProfile){Get-FormProfile}else{Get-BeeProfile $script:currentProfile.id}
        $safeInput=Get-SafeTestInput ([int]$profileForLimit.context) $outputTokens
        if($safeInput-lt 256){throw "Context $($profileForLimit.context) слишком мал для output $outputTokens. Уменьшите output или увеличьте context."}
        $adjustment=''
        if($promptTokens-gt$safeInput){$adjustment="Input автоматически уменьшен с $promptTokens до $safeInput tokens, чтобы поместиться в context $($profileForLimit.context).";$promptTokens=$safeInput;(UI 'TestPromptTokens').Text=[string]$promptTokens;Update-TestLimitHint}
        if ($applyProfile) {
            $p = Save-CurrentProfile
            if (-not $p) { return }
            $oldStatus = Get-BeeServerStatus
            $manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\server-manager.ps1'
            $line = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Start -ProfileId "{1}"' -f $manager,$p.id
            Start-Process -FilePath 'powershell.exe' -ArgumentList $line -WindowStyle Hidden | Out-Null
            $script:pendingBenchmark = [pscustomobject]@{ProfileId=$p.id;OldPid=$oldStatus.Pid;PromptTokens=$promptTokens;OutputTokens=$outputTokens;Timeout=$timeout;Adjustment=$adjustment;StartedAt=(Get-Date);Deadline=(Get-Date).AddSeconds(140)}
            (UI 'TestState').Text='LOADING SERVER'
            (UI 'TestResult').Text=($adjustment+"`nПрофиль сохранён. Сервер перезапускается; benchmark начнётся автоматически после /health.").Trim()
        } else {
            $p = Get-BeeProfile $script:currentProfile.id
            $result = Start-BeeBenchmark -ProfileId $p.id -PromptTokens $promptTokens -OutputTokens $outputTokens -TimeoutSec $timeout
            (UI 'TestState').Text='STARTING'
            (UI 'TestResult').Text=($adjustment+"`nBenchmark PID $($result.Pid) запущен на текущем сервере.").Trim()
        }
    } catch { Show-Message $_.Exception.Message 'Не удалось запустить тест' Error }
}

function End-Benchmark {
    try {
        $script:pendingBenchmark = $null
        $result = Stop-BeeBenchmark
        (UI 'TestState').Text='STOPPED'
        (UI 'TestResult').Text=$result.Message
    } catch { Show-Message $_.Exception.Message 'Не удалось остановить тест' Error }
}

function Load-TeamAgent($Agent) {
    if(-not$Agent){return}
    $script:currentTeamAgent=$Agent
    (UI 'AgentId').Text=[string]$Agent.Id
    (UI 'AgentDescription').Text=[string]$Agent.Description
    (UI 'AgentModel').ItemsSource=@($script:teamSnapshot.Models)
    (UI 'AgentModel').SelectedItem=[string]$Agent.Model
    if(-not(UI 'AgentModel').SelectedItem-and$Agent.Model){(UI 'AgentModel').Text=[string]$Agent.Model}
    (UI 'AgentMode').SelectedItem=[string]$Agent.Mode
    (UI 'AgentEnabled').IsChecked=-not[bool]$Agent.Disabled
    (UI 'AgentStatusBadge').Text=[string]$Agent.Status
    (UI 'AgentError').Text=[string]$Agent.Errors
    (UI 'AgentDelegatable').IsChecked=[bool]$Agent.DelegateAllowed
    (UI 'AgentDelegatable').IsEnabled=($Agent.Id-notin@('team-lead','build'))
    (UI 'AgentPrompt').Text=[string]$Agent.Prompt
    (UI 'AgentPermissions').Text=$(if($Agent.Permissions){"Эффективные правила:`n$($Agent.Permissions)"}else{'Нет собственных правил; действуют глобальные разрешения OpenCode.'})
    (UI 'AgentDelegates').Text=$(if(@($Agent.Delegates).Count){"Может делегировать:`n$(@($Agent.Delegates)-join [Environment]::NewLine)"}else{'Делегирование другим агентам не настроено.'})
    (UI 'DeleteAgent').IsEnabled=[bool]$Agent.CanDelete
    $script:teamSkills.Clear()
    foreach($skill in @($script:teamSnapshot.Skills)){
        $script:teamSkills.Add([pscustomobject]@{Id=$skill.Id;Description=$(if($skill.Description){$skill.Description}else{$skill.Error});Status=$(if($skill.Valid){$(if($skill.Id-in@($Agent.Skills)){'ASSIGNED'}else{'AVAILABLE'})}else{'INVALID'});Path=$skill.Path;Valid=[bool]$skill.Valid;IsAssigned=[bool]($skill.Id-in@($Agent.Skills))})
    }
    foreach($missing in @($Agent.Skills|Where-Object{$_-notin@($script:teamSnapshot.Skills.Id)})){$script:teamSkills.Add([pscustomobject]@{Id=$missing;Description='Назначен в OpenCode, но каталог skill отсутствует';Status='MISSING';Path='';Valid=$false;IsAssigned=$true})}
    $script:teamMcps.Clear()
    foreach($mcp in @($script:teamSnapshot.Mcps)){$script:teamMcps.Add([pscustomobject]@{Id=$mcp.Id;Description=$mcp.Description;Command=$mcp.Command;Status=$mcp.Status;PathExists=$mcp.PathExists;IsAssigned=[bool]($mcp.Id-in@($Agent.Mcps));IsEnabled=[bool]$mcp.Enabled})}
}

function Refresh-TeamView([string]$SelectId='') {
    if($script:teamRefreshInProgress){return}
    $script:teamRefreshInProgress=$true
    try{
        $previous=if($SelectId){$SelectId}elseif($script:currentTeamAgent){[string]$script:currentTeamAgent.Id}else{'team-lead'}
        $script:teamSnapshot=Get-BeeTeamSnapshot
        $serenaState=if($script:teamSnapshot.SerenaWarningCount){"Serena: предупреждений $($script:teamSnapshot.SerenaWarningCount)"}else{'Serena: готова'}
        (UI 'TeamSummary').Text="Team Lead → FAST по умолчанию | $($script:teamSnapshot.ActiveAgents) активных агентов | одновременно 1 | обычный лимит 2 | $serenaState | диагностика: $($script:teamSnapshot.ErrorCount)"
        (UI 'TeamConfigInfo').Text="$($script:teamSnapshot.ConfigPath) | обновлено $($script:teamSnapshot.LastWriteTime.ToString('dd.MM.yyyy HH:mm:ss'))"
        $teamView=[System.Windows.Data.CollectionViewSource]::GetDefaultView(@($script:teamSnapshot.Agents))
        $teamView.GroupDescriptions.Clear()
        [void]$teamView.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription 'Category'))
        (UI 'TeamAgentList').ItemsSource=$teamView
        $selected=@($script:teamSnapshot.Agents|Where-Object{$_.Id-eq$previous}|Select-Object -First 1)
        if(-not$selected.Count){$selected=@($script:teamSnapshot.Agents|Select-Object -First 1)}
        if($selected.Count){(UI 'TeamAgentList').SelectedItem=$selected[0];Load-TeamAgent $selected[0]}
        (UI 'TeamStatus').Text=$(if($script:teamSnapshot.SerenaWarningCount){@($script:teamSnapshot.SerenaWarnings)-join[Environment]::NewLine}else{'Конфигурация прочитана. Serena-проекты проиндексированы или ещё не содержат распознаваемого исходного кода.'})
        Refresh-FullAccessUi
    }catch{(UI 'TeamSummary').Text='Не удалось прочитать AI-команду';(UI 'TeamStatus').Text=$_.Exception.Message}
    finally{$script:teamRefreshInProgress=$false}
}

function Refresh-FullAccessUi {
    try{
        $status=Get-BeeFullAccessStatus
        if($status.Enabled){
            (UI 'FullAccessStatus').Text="Полный доступ: ВКЛЮЧЁН$(if($status.EnabledAt){" · с $($status.EnabledAt)"})"
            (UI 'FullAccessStatus').Foreground=[Windows.Media.Brushes]::Orange
            (UI 'FullAccessCard').BorderBrush=[Windows.Media.Brushes]::DarkOrange
            (UI 'ToggleFullAccess').Content='Выключить полный доступ'
            (UI 'ToggleFullAccess').Background=[Windows.Media.Brushes]::DarkRed
        }elseif($status.Inconsistent){
            (UI 'FullAccessStatus').Text='Полный доступ: состояние требует восстановления'
            (UI 'FullAccessStatus').Foreground=[Windows.Media.Brushes]::Tomato
            (UI 'FullAccessCard').BorderBrush=[Windows.Media.Brushes]::Tomato
            (UI 'ToggleFullAccess').Content='Восстановить обычный режим'
            (UI 'ToggleFullAccess').Background=[Windows.Media.Brushes]::DarkRed
        }else{
            (UI 'FullAccessStatus').Text='Полный доступ: выключен · действуют обычные подтверждения'
            (UI 'FullAccessStatus').Foreground=[Windows.Media.Brushes]::LightGreen
            (UI 'FullAccessCard').BorderBrush=[Windows.Media.Brushes]::DimGray
            (UI 'ToggleFullAccess').Content='Включить полный доступ'
            (UI 'ToggleFullAccess').Background=[Windows.Media.Brushes]::DarkOrange
        }
    }catch{(UI 'FullAccessStatus').Text="Полный доступ: ошибка проверки — $($_.Exception.Message)";(UI 'FullAccessStatus').Foreground=[Windows.Media.Brushes]::Tomato}
}

function Toggle-FullAccessFromUi {
    try{
        $status=Get-BeeFullAccessStatus
        if($status.Enabled-or$status.Inconsistent){
            [void](Set-BeeFullAccess -Enabled $false -Source 'BeeForge UI')
            Refresh-TeamView 'team-lead'
            (UI 'TeamStatus').Text='Обычные разрешения восстановлены.'
            return
        }
        $warning="Включить ПОЛНЫЙ ДОСТУП для всех агентов OpenCode?`n`nАгенты смогут без системных запросов разрешения читать и изменять любые доступные файлы, запускать команды, использовать интернет и MCP. Включайте режим только для доверенной задачи. Действие будет записано в журнал."
        if([Windows.MessageBox]::Show($window,$warning,'Полный доступ','YesNo','Warning')-ne'Yes'){return}
        [void](Set-BeeFullAccess -Enabled $true -Source 'BeeForge UI')
        Refresh-TeamView 'team-lead'
        (UI 'TeamStatus').Text='Полный доступ включён. Для уже открытой сессии OpenCode может потребоваться новая сессия.'
    }catch{Show-Message $_.Exception.Message 'Не удалось изменить полный доступ' Error;Refresh-FullAccessUi}
}

function Commit-TeamGridEdits {
    [void](UI 'TeamSkillsGrid').CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true);[void](UI 'TeamSkillsGrid').CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
    [void](UI 'TeamMcpGrid').CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true);[void](UI 'TeamMcpGrid').CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
}

function Save-TeamAgentForm {
    try{
        if(-not$script:currentTeamAgent){throw 'Выберите агента'};Commit-TeamGridEdits
        $skills=@($script:teamSkills|Where-Object{$_.IsAssigned}|ForEach-Object{$_.Id})
        $mcps=@($script:teamMcps|Where-Object{$_.IsAssigned}|ForEach-Object{$_.Id})
        $enabledMcps=@($script:teamMcps|Where-Object{$_.IsEnabled}|ForEach-Object{$_.Id})
        $model=[string](UI 'AgentModel').SelectedItem;if(-not$model){$model=[string](UI 'AgentModel').Text}
        $mode=[string](UI 'AgentMode').SelectedItem
        [void](Save-BeeAgent -Id $script:currentTeamAgent.Id -Description (UI 'AgentDescription').Text -Model $model -Mode $mode -Disabled (-not[bool](UI 'AgentEnabled').IsChecked) -Prompt (UI 'AgentPrompt').Text -SkillIds $skills -McpIds $mcps -EnabledMcpIds $enabledMcps -DelegateAllowed ([bool](UI 'AgentDelegatable').IsChecked))
        $id=[string]$script:currentTeamAgent.Id;Refresh-TeamView $id;(UI 'TeamStatus').Text="Агент '$id' сохранён. OpenCode перечитает конфигурацию при следующем запуске/перезагрузке."
    }catch{Show-Message $_.Exception.Message 'Не удалось сохранить агента' Error}
}

function New-TeamAgentFromUi {
    try{
        $id=[Microsoft.VisualBasic.Interaction]::InputBox('ID нового агента: строчные латинские буквы, цифры и дефисы.','Новый агент','new-specialist').Trim();if(-not$id){return}
        $description=[Microsoft.VisualBasic.Interaction]::InputBox('Профессиональная роль и краткое назначение агента.','Описание агента','Новый специалист — описание задач').Trim();if(-not$description){return}
        $model=if($script:teamSnapshot.Models.Count){[string]$script:teamSnapshot.Models[0]}else{''}
        [void](New-BeeAgent -Id $id -Description $description -Model $model);Refresh-TeamView $id
    }catch{Show-Message $_.Exception.Message 'Не удалось создать агента' Error}
}

function Clone-TeamAgentFromUi {
    try{
        if(-not$script:currentTeamAgent){throw 'Выберите агента'};$suggestion=([string]$script:currentTeamAgent.Id+'-copy')
        $id=[Microsoft.VisualBasic.Interaction]::InputBox("Новый ID для копии '$($script:currentTeamAgent.Id)':",'Клонировать агента',$suggestion).Trim();if(-not$id){return}
        [void](Copy-BeeAgent -SourceId $script:currentTeamAgent.Id -NewId $id);Refresh-TeamView $id
    }catch{Show-Message $_.Exception.Message 'Не удалось клонировать агента' Error}
}

function Delete-TeamAgentFromUi {
    try{
        if(-not$script:currentTeamAgent){throw 'Выберите агента'};$id=[string]$script:currentTeamAgent.Id
        if([Windows.MessageBox]::Show($window,"Удалить агента '$id'? Перед удалением будет создана резервная копия OpenCode.",'Удаление агента','YesNo','Warning')-ne'Yes'){return}
        [void](Remove-BeeAgent $id);$script:currentTeamAgent=$null;Refresh-TeamView 'team-lead'
    }catch{Show-Message $_.Exception.Message 'Не удалось удалить агента' Error}
}

function Restore-TeamFromBackup {
    try{
        if([Windows.MessageBox]::Show($window,'Восстановить последнюю конфигурацию, созданную редактором AI-команды? Текущее состояние также будет сохранено.','Восстановление OpenCode','YesNo','Warning')-ne'Yes'){return}
        $result=Restore-BeeTeamConfig;Refresh-TeamView 'team-lead';(UI 'TeamStatus').Text="Восстановлено из $($result.Restored)"
    }catch{Show-Message $_.Exception.Message 'Не удалось восстановить конфигурацию' Error}
}

function Start-TeamMcpCheck {
    try{Commit-TeamGridEdits;$row=(UI 'TeamMcpGrid').SelectedItem;if(-not$row){throw 'Выберите MCP в таблице'};$result=Start-BeeMcpTest -McpId $row.Id -TimeoutSec 10;(UI 'TeamMcpTestStatus').Text="RUNNING | $($row.Id) | PID $($result.Pid)"}
    catch{Show-Message $_.Exception.Message 'Не удалось проверить MCP' Error}
}

function Update-TelegramStatus {
    try {
        $status=Get-BeeTelegramBridgeStatus
        $state=([string]$status.State).ToUpperInvariant()
        $details=if($status.Running){"PID $($status.Pid)"}else{'процесс не запущен'}
        if($status.Message){$details+=" | $($status.Message)"}
        (UI 'TelegramStatus').Text="$state | $details"
        (UI 'TelegramTokenState').Text=if($status.TokenConfigured){'Токен сохранён и защищён Windows DPAPI'}else{'Токен не сохранён'}
    } catch {(UI 'TelegramStatus').Text="ОШИБКА | $($_.Exception.Message)"}
}

function Refresh-TelegramView {
    try {
        $config=Get-BeeTelegramConfig
        (UI 'TelegramEnabled').IsChecked=[bool]$config.enabled
        (UI 'TelegramUserId').Text=[string]$config.allowedUserId
        (UI 'TelegramChatId').Text=[string]$config.allowedChatId
        (UI 'TelegramSummaryMinutes').Text='Отключены — используйте /status'
        (UI 'TelegramNotifyDelegation').IsChecked=[bool]$config.notifyDelegation
        (UI 'TelegramNotifyCompletion').IsChecked=[bool]$config.notifyCompletion
        (UI 'TelegramNotifyErrors').IsChecked=[bool]$config.notifyErrors
        (UI 'TelegramPinnedStatus').IsChecked=if($null-eq$config.pinnedStatus){$true}else{[bool]$config.pinnedStatus}
        (UI 'TelegramVoiceEnabled').IsChecked=if($null-eq$config.voiceEnabled){$true}else{[bool]$config.voiceEnabled}
        $voiceModel=if([string]::IsNullOrWhiteSpace([string]$config.voiceModel)){'small'}else{[string]$config.voiceModel}
        foreach($item in (UI 'TelegramVoiceModel').Items){if([string]$item.Content-eq$voiceModel){(UI 'TelegramVoiceModel').SelectedItem=$item;break}}
        $telegramProjects.Clear();foreach($project in @($config.allowedProjects)){$telegramProjects.Add([string]$project)}
        (UI 'TelegramToken').Password=''
        Update-TelegramStatus
    } catch {Show-Message $_.Exception.Message 'Telegram Bridge' Error}
}

function Save-TelegramForm {
    try {
        $wasRunning=(Get-BeeTelegramBridgeStatus).Running
        $existing=Get-BeeTelegramConfig
        $config=[pscustomobject]@{
            enabled=[bool](UI 'TelegramEnabled').IsChecked
            allowedUserId=(UI 'TelegramUserId').Text.Trim()
            allowedChatId=(UI 'TelegramChatId').Text.Trim()
            bridgePort=47655
            summaryIntervalMinutes=0
            notifyDelegation=[bool](UI 'TelegramNotifyDelegation').IsChecked
            notifyCompletion=[bool](UI 'TelegramNotifyCompletion').IsChecked
            notifyErrors=[bool](UI 'TelegramNotifyErrors').IsChecked
            muted=[bool]$existing.muted
            allowedProjects=@($telegramProjects)
            allowPreviouslyOpenedProjects=if($null-eq$existing.allowPreviouslyOpenedProjects){$true}else{[bool]$existing.allowPreviouslyOpenedProjects}
            defaultProjectRoot=if([string]::IsNullOrWhiteSpace([string]$existing.defaultProjectRoot)){'C:\AI\Projects'}else{[string]$existing.defaultProjectRoot}
            pinnedStatus=[bool](UI 'TelegramPinnedStatus').IsChecked
            voiceEnabled=[bool](UI 'TelegramVoiceEnabled').IsChecked
            voicePort=if($null-eq$existing.voicePort){47656}else{[int]$existing.voicePort}
            voiceModel=if($null-ne(UI 'TelegramVoiceModel').SelectedItem){[string](UI 'TelegramVoiceModel').SelectedItem.Content}else{'small'}
            voiceLanguage='auto'
        }
        [void](Save-BeeTelegramConfig $config)
        $newToken=(UI 'TelegramToken').Password
        if($newToken){Set-BeeTelegramToken $newToken}
        if($wasRunning){[void](Stop-BeeTelegramBridge);if($config.enabled){[void](Start-BeeTelegramBridge)}}
        Refresh-TelegramView
        (UI 'TelegramStatus').Text='СОХРАНЕНО | настройки применены; для OpenCode-плагина нужен следующий запуск OpenCode'
        return $true
    } catch {Show-Message $_.Exception.Message 'Не удалось сохранить Telegram' Error;return $false}
}

function Add-TelegramProject {
    $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description='Выберите проект, которым разрешено управлять через Telegram'
    $dialog.ShowNewFolderButton=$false
    if($dialog.ShowDialog()-eq[System.Windows.Forms.DialogResult]::OK){
        $full=[IO.Path]::GetFullPath($dialog.SelectedPath)
        if(-not(@($telegramProjects)|Where-Object{[string]::Equals([string]$_,$full,[StringComparison]::OrdinalIgnoreCase)})){$telegramProjects.Add($full)}
    }
}

function Start-TelegramFromUi {
    try{$script:telegramManualStop=$false;if(-not(Save-TelegramForm)){return};if(-not[bool](UI 'TelegramEnabled').IsChecked){throw 'Сначала включите интеграцию'};$status=Start-BeeTelegramBridge;Update-TelegramStatus;if(-not$status.Running){throw "Мост не запустился: $($status.Message)"}}
    catch{Show-Message $_.Exception.Message 'Запуск Telegram Bridge' Error}
}

(UI 'ProfileList').Add_SelectionChanged({ if ((UI 'ProfileList').SelectedItem) { Load-Profile (UI 'ProfileList').SelectedItem } })
(UI 'RefreshModels').Add_Click({ Refresh-ModelList })
(UI 'BrowseModel').Add_Click({ $d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='GGUF models (*.gguf)|*.gguf'; if($d.ShowDialog()) {(UI 'ModelPath').Text=$d.FileName;Refresh-VisionProjectorList -PreferDetected;Update-Preview} })
(UI 'BrowseMmproj').Add_Click({ $d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='Vision projector (*.gguf)|*.gguf'; if($d.ShowDialog()) {(UI 'MmprojPath').Text=$d.FileName;Update-VisionHint;Queue-ResourceEstimate;Update-Preview} })
(UI 'BrowseRuntime').Add_Click({ $d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='llama-server.exe|llama-server.exe'; if($d.ShowDialog()) {(UI 'ServerPath').Text=$d.FileName;Update-Preview} })
(UI 'AddAdvanced').Add_Click({ $advanced.Add([pscustomobject]@{flag='--';value=''}) })
(UI 'RemoveAdvanced').Add_Click({ $item=(UI 'AdvancedGrid').SelectedItem; if($item){$advanced.Remove($item)} })
(UI 'RefreshEstimate').Add_Click({ Update-ResourceEstimate })
foreach($controlName in @('Context','Parallel','Batch','Ubatch','KvTailTokens')) { (UI $controlName).Add_TextChanged({ Queue-ResourceEstimate }) }
foreach($controlName in @('GpuLayers','KvK','KvV','KvTailType')) { (UI $controlName).Add_SelectionChanged({ Queue-ResourceEstimate }) }
foreach($controlName in @('FlashAttention','MtpEnabled','VisionEnabled','VisionOffload')) { (UI $controlName).Add_Checked({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview }); (UI $controlName).Add_Unchecked({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview }) }
(UI 'ModelPath').Add_SelectionChanged({ Refresh-VisionProjectorList -PreferDetected; Queue-ResourceEstimate; Update-Preview })
(UI 'ModelPath').Add_LostKeyboardFocus({ Refresh-VisionProjectorList -PreferDetected; Queue-ResourceEstimate; Update-Preview })
(UI 'MmprojPath').Add_SelectionChanged({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview })
(UI 'MmprojPath').Add_LostKeyboardFocus({ Update-VisionHint; Queue-ResourceEstimate; Update-Preview })
(UI 'Context').Add_TextChanged({ Update-TestLimitHint })
(UI 'TestOutputTokens').Add_SelectionChanged({ Update-TestLimitHint })
(UI 'TestOutputTokens').Add_LostKeyboardFocus({ Update-TestLimitHint })
(UI 'SaveProfile').Add_Click({ try { Save-CurrentProfile | Out-Null } catch { Show-Message $_.Exception.Message 'Ошибка сохранения' Error } })
(UI 'ApplyRestart').Add_Click({ Start-SelectedProfile $true })
(UI 'StartServer').Add_Click({ Start-SelectedProfile $true })
(UI 'StopServer').Add_Click({ try { $r=Stop-BeeServer;(UI 'StatusLine').Text=$r.Message } catch { Show-Message $_.Exception.Message 'Ошибка остановки' Error } })
(UI 'StartTest').Add_Click({ Begin-Benchmark })
(UI 'StopTest').Add_Click({ End-Benchmark })
(UI 'TeamAgentList').Add_SelectionChanged({if((UI 'TeamAgentList').SelectedItem){Load-TeamAgent (UI 'TeamAgentList').SelectedItem}})
(UI 'RefreshTeam').Add_Click({Refresh-TeamView})
(UI 'ToggleFullAccess').Add_Click({Toggle-FullAccessFromUi})
(UI 'OpenTeamConfig').Add_Click({try{Start-Process notepad.exe -ArgumentList ('"'+(Get-BeeTeamPaths).Config+'"')}catch{Show-Message $_.Exception.Message 'OpenCode config' Error}})
(UI 'OpenSelectedSkill').Add_Click({try{$row=(UI 'TeamSkillsGrid').SelectedItem;if(-not$row){throw 'Выберите skill в таблице'};if(-not(Test-Path -LiteralPath $row.Path)){throw "SKILL.md не найден: $($row.Path)"};Start-Process notepad.exe -ArgumentList ('"'+$row.Path+'"')}catch{Show-Message $_.Exception.Message 'Открыть skill' Error}})
(UI 'NewAgent').Add_Click({New-TeamAgentFromUi})
(UI 'CloneAgent').Add_Click({Clone-TeamAgentFromUi})
(UI 'DeleteAgent').Add_Click({Delete-TeamAgentFromUi})
(UI 'SaveAgent').Add_Click({Save-TeamAgentForm})
(UI 'RestoreTeamConfig').Add_Click({Restore-TeamFromBackup})
(UI 'TestSelectedMcp').Add_Click({Start-TeamMcpCheck})
(UI 'StopMcpCheck').Add_Click({try{[void](Stop-BeeMcpTest);(UI 'TeamMcpTestStatus').Text='STOPPED | проверка MCP остановлена'}catch{Show-Message $_.Exception.Message 'Остановить MCP-тест' Error}})
(UI 'TelegramSave').Add_Click({[void](Save-TelegramForm)})
(UI 'TelegramTest').Add_Click({try{if((UI 'TelegramToken').Password){Set-BeeTelegramToken (UI 'TelegramToken').Password};$bot=Test-BeeTelegramConnection;Show-Message "Соединение установлено: @$($bot.username)" 'Telegram Bot';Refresh-TelegramView}catch{Show-Message $_.Exception.Message 'Проверка Telegram' Error}})
(UI 'TelegramStart').Add_Click({Start-TelegramFromUi})
(UI 'TelegramStop').Add_Click({try{$script:telegramManualStop=$true;[void](Stop-BeeTelegramBridge);Update-TelegramStatus}catch{Show-Message $_.Exception.Message 'Остановка Telegram Bridge' Error}})
(UI 'TelegramOpenLog').Add_Click({try{Open-BeeTelegramLog}catch{Show-Message $_.Exception.Message 'Журнал Telegram' Error}})
(UI 'TelegramAddProject').Add_Click({Add-TelegramProject})
(UI 'TelegramRemoveProject').Add_Click({$selected=(UI 'TelegramProjects').SelectedItem;if($null-ne$selected){[void]$telegramProjects.Remove($selected)}})
(UI 'OpenLiveLog').Add_Click({ try { Open-BeeLiveLog } catch { Show-Message $_.Exception.Message 'Live log' Error } })
(UI 'OpenLogs').Add_Click({ Start-Process explorer.exe -ArgumentList ('"'+(Get-BeeLogPaths).Directory+'"') })
(UI 'NewProfile').Add_Click({ try { $base=Get-BeeNewProfileTemplate;$base.id='profile-'+[guid]::NewGuid().ToString('N').Substring(0,10);$base.name='Новый профиль';$base.protected=$false;$s=Get-BeeProfileStore;$s.profiles=@($s.profiles)+$base;Save-BeeProfileStore $s;Refresh-ProfileList $base.id } catch { Show-Message $_.Exception.Message 'Ошибка' Error } })
(UI 'CloneProfile').Add_Click({ try { $p=Get-FormProfile;$p.id='profile-'+[guid]::NewGuid().ToString('N').Substring(0,10);$p.name=$p.name+' — копия';$p.protected=$false;$s=Get-BeeProfileStore;$s.profiles=@($s.profiles)+$p;Save-BeeProfileStore $s;Refresh-ProfileList $p.id } catch { Show-Message $_.Exception.Message 'Ошибка' Error } })
(UI 'DeleteProfile').Add_Click({ try { $p=$script:currentProfile;$s=Get-BeeProfileStore;if(@($s.profiles).Count-le1){throw 'Нельзя удалить единственный профиль. Сначала создайте или импортируйте другой.'};if([Windows.MessageBox]::Show($window,"Удалить профиль $($p.name)?",'Подтверждение','YesNo','Warning')-eq'Yes'){$s.profiles=@($s.profiles|Where-Object{$_.id-ne$p.id});$nextId=[string]@($s.profiles)[0].id;if($s.activeProfileId-eq$p.id){$s.activeProfileId=$nextId};if($s.lastGoodProfileId-eq$p.id){$s.lastGoodProfileId=$nextId};Save-BeeProfileStore $s;Refresh-ProfileList $nextId} } catch { Show-Message $_.Exception.Message 'Удаление' Error } })
(UI 'ExportProfile').Add_Click({ try { $d=New-Object Microsoft.Win32.SaveFileDialog;$d.Filter='JSON profile (*.json)|*.json';$d.FileName=$script:currentProfile.id+'.json';if($d.ShowDialog()){$json=Get-FormProfile|ConvertTo-Json -Depth 20;[IO.File]::WriteAllText($d.FileName,$json,[Text.UTF8Encoding]::new($true))} } catch { Show-Message $_.Exception.Message 'Экспорт' Error } })
(UI 'ImportProfile').Add_Click({ try { $d=New-Object Microsoft.Win32.OpenFileDialog;$d.Filter='JSON profile (*.json)|*.json';if($d.ShowDialog()){$p=[IO.File]::ReadAllText($d.FileName,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json;$p.id='profile-'+[guid]::NewGuid().ToString('N').Substring(0,10);$p.protected=$false;$v=Test-BeeProfile $p;if(-not$v.Valid){throw($v.Errors-join"`n")};$s=Get-BeeProfileStore;$s.profiles=@($s.profiles)+$p;Save-BeeProfileStore $s;Refresh-ProfileList $p.id} } catch { Show-Message $_.Exception.Message 'Импорт' Error } })
(UI 'Tabs').Add_SelectionChanged({
    param($sender,$eventArgs)
    # SelectionChanged is routed: ComboBox/ListBox/DataGrid events inside a tab
    # also reach the TabControl. React only to an actual tab selection change.
    if($eventArgs.Source -ne $sender){return}
    if ($sender.SelectedItem -eq (UI 'CommandTab')) { Update-Preview }
    if ($sender.SelectedItem -eq (UI 'ResourcesTab')) { Update-ResourceEstimate }
    if ($sender.SelectedItem -eq (UI 'TeamTab')) { Refresh-TeamView }
    if ($sender.SelectedItem -eq (UI 'TelegramTab')) { Refresh-TelegramView }
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    try {
        $s=Get-BeeServerStatus
        if ($script:pendingBenchmark) {
            $managerError=Join-Path (Get-BeeLogPaths).Directory 'manager-error.log'
            if ((Test-Path -LiteralPath $managerError) -and (Get-Item -LiteralPath $managerError).LastWriteTime -gt $script:pendingBenchmark.StartedAt) {
                (UI 'TestState').Text='FAILED';(UI 'TestResult').Text=(Get-Content -Raw -LiteralPath $managerError);$script:pendingBenchmark=$null
            } elseif ((Get-Date) -gt $script:pendingBenchmark.Deadline) {
                (UI 'TestState').Text='FAILED'; (UI 'TestResult').Text='Сервер не стал READY за 140 секунд; benchmark не запущен.'; $script:pendingBenchmark=$null
            } elseif ($s.Ready -and $s.Pid -and $s.Pid -ne $script:pendingBenchmark.OldPid) {
                try {
                    $started=Start-BeeBenchmark -ProfileId $script:pendingBenchmark.ProfileId -PromptTokens $script:pendingBenchmark.PromptTokens -OutputTokens $script:pendingBenchmark.OutputTokens -TimeoutSec $script:pendingBenchmark.Timeout
                    (UI 'TestState').Text='RUNNING'; (UI 'TestResult').Text="Benchmark PID $($started.Pid) запущен после успешного /health."; $script:pendingBenchmark=$null
                } catch { (UI 'TestState').Text='FAILED';(UI 'TestResult').Text=$_.Exception.Message;$script:pendingBenchmark=$null }
            }
        }
        $bench=Get-BeeBenchmarkStatus
        if ($bench.Running -or $bench.state -in @('Completed','Failed','Stopped')) {
            (UI 'TestState').Text=[string]$bench.state.ToUpperInvariant()
            $promptSpeed=if($bench.promptTps){[double]$bench.promptTps}elseif($s.PromptTPS){[double]$s.PromptTPS}else{$null}
            $decodeSpeed=if($bench.decodeTps){[double]$bench.decodeTps}elseif($s.DecodeTPS){[double]$s.DecodeTPS}else{$null}
            (UI 'TestPromptTps').Text=if($promptSpeed){'{0:N2} tok/s' -f $promptSpeed}else{'— tok/s'}
            (UI 'TestDecodeTps').Text=if($decodeSpeed){'{0:N2} tok/s' -f $decodeSpeed}else{'— tok/s'}
            (UI 'TestElapsed').Text=if($bench.elapsedSec){'{0:N1} сек' -f [double]$bench.elapsedSec}else{'— сек'}
            $inputCount=if($bench.promptTokens){$bench.promptTokens}elseif($s.PromptTokens){$s.PromptTokens}else{'—'}
            $outputCount=if($bench.outputTokens){$bench.outputTokens}elseif($s.DecodedTokens){$s.DecodedTokens}else{'—'}
            (UI 'TestTokens').Text="Input: $inputCount | Output: $outputCount"
            if(-not $bench.Running){(UI 'TestResult').Text="$($bench.message)`nPrompt: $inputCount tokens @ $((UI 'TestPromptTps').Text)`nGeneration: $outputCount tokens @ $((UI 'TestDecodeTps').Text)`nElapsed: $((UI 'TestElapsed').Text)`nFinish: $($bench.finishReason)`n`n$($bench.contentPreview)"}
        }
        $mcpTest=Get-BeeMcpTestStatus;$mcpSignature="$($mcpTest.state)|$($mcpTest.mcp)|$($mcpTest.message)"
        if($mcpSignature-ne$script:lastMcpTestSignature){$script:lastMcpTestSignature=$mcpSignature;$stateText=([string]$mcpTest.state).ToUpperInvariant();(UI 'TeamMcpTestStatus').Text="$stateText | $($mcpTest.mcp) | $($mcpTest.message)"}
        Update-TelegramStatus
        $state=if($s.Ready){'READY'}elseif($s.Running){'LOADING'}else{'STOPPED'}
        (UI 'HeaderStatus').Text="$state | PID $($s.Pid) | uptime $($s.Uptime)"
        $vram=if($null-ne$s.VramUsedMiB){"$($s.VramUsedMiB)/$($s.VramTotalMiB) MiB"}else{'n/a'}
        $pt=if($null-ne$s.PromptTPS){"$($s.PromptTPS) tok/s"}else{'n/a'};$dt=if($null-ne$s.DecodeTPS){"$($s.DecodeTPS) tok/s"}else{'n/a'}
        (UI 'StatusLine').Text="$state | $($s.Profile) | ctx $($s.Context) | VRAM $vram | Shared $($s.SharedVram) | RAM $($s.RamUsedGiB) GiB | prompt $pt | decode $dt"
        (UI 'ActualVram').Text=if($null-ne$s.VramUsedMiB){'{0:N2} / {1:N2} GiB' -f ($s.VramUsedMiB/1024.0),($s.VramTotalMiB/1024.0)}else{'н/д'}
        (UI 'ActualRam').Text=if($null-ne$s.RamUsedGiB){'{0:N1} / {1:N1} GiB' -f $s.RamUsedGiB,$s.RamTotalGiB}else{'н/д'}
        if(-not$s.Running){$ef=Join-Path (Get-BeeLogPaths).Directory 'manager-error.log';if(Test-Path $ef){$e=(Get-Content -Raw -LiteralPath $ef);if($e){(UI 'StatusLine').Text="ОШИБКА: $e"}}}
    } catch { (UI 'HeaderStatus').Text='Ошибка статуса' }
})
$telegramWatchdogTimer = New-Object Windows.Threading.DispatcherTimer
$telegramWatchdogTimer.Interval = [TimeSpan]::FromSeconds(3)
$telegramWatchdogTimer.Add_Tick({
    try {
        $telegramBridgeStatus=Get-BeeTelegramBridgeStatus
        if(-not$telegramBridgeStatus.Running -and -not$script:telegramManualStop){
            $telegramConfig=Get-BeeTelegramConfig
            $restartDue=(-not$script:lastTelegramRestartAt)-or(((Get-Date)-$script:lastTelegramRestartAt).TotalSeconds-ge15)
            if($telegramConfig.enabled-and$restartDue){
                $script:lastTelegramRestartAt=Get-Date
                [void](Start-BeeTelegramBridge)
            }
        }
        Update-TelegramStatus
    } catch {
        (UI 'TelegramStatus').Text="ОШИБКА АВТОВОССТАНОВЛЕНИЯ | $($_.Exception.Message)"
    }
})
$window.Add_Closed({ $timer.Stop(); $telegramWatchdogTimer.Stop(); $resourceDebounce.Stop(); try{[void](Stop-BeeMcpTest)}catch{} })
Refresh-ModelList
Refresh-ProfileList (Get-BeeProfileStore).activeProfileId
$script:telegramManualStop=$false
$script:lastTelegramRestartAt=$null
Refresh-TelegramView
try{$telegramStartupConfig=Get-BeeTelegramConfig;if($telegramStartupConfig.enabled){[void](Start-BeeTelegramBridge);Update-TelegramStatus}}catch{(UI 'TelegramStatus').Text="ОШИБКА ЗАПУСКА | $($_.Exception.Message)"}
if($env:BEEFORGE_TELEGRAM_SMOKE_TEST-eq'1'){
    (UI 'Tabs').SelectedItem=(UI 'TelegramTab')
    if((UI 'Tabs').SelectedItem-ne(UI 'TelegramTab')){throw 'Telegram не стала активной вкладкой'}
    if(-not(UI 'TelegramStatus').Text){throw 'Статус Telegram пуст'}
    if([Windows.Controls.ScrollViewer]::GetHorizontalScrollBarVisibility((UI 'TelegramProjects'))-ne[Windows.Controls.ScrollBarVisibility]::Disabled){throw 'Горизонтальная прокрутка проектов не отключена'}
    Write-Output ("TELEGRAM_TAB_SMOKE_OK | {0} projects | {1}" -f (UI 'TelegramProjects').Items.Count,(UI 'TelegramStatus').Text)
    $window.Close();return
}
if($env:BEEFORGE_TEAM_SMOKE_TEST-eq'1'){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    (UI 'Tabs').SelectedItem=(UI 'TeamTab')
    if((UI 'TeamAgentList').Items.Count-gt1){(UI 'TeamAgentList').SelectedIndex=1}
    $watch.Stop()
    if((UI 'Tabs').SelectedItem-ne(UI 'TeamTab')){throw 'AI-команда не стала активной вкладкой'}
    if(-not$script:teamSnapshot-or-not(UI 'TeamAgentList').Items.Count){throw 'AI-команда не загрузила агентов'}
    if(-not(UI 'FullAccessStatus').Text-or(UI 'FullAccessStatus').Text-like'*проверка*'){throw 'Состояние полного доступа не загрузилось'}
    if(-not(UI 'ToggleFullAccess').Content){throw 'Кнопка полного доступа не создана'}
    $longNames=@($script:teamSnapshot.Agents|Where-Object{$_.DisplayName.Length-gt64})
    if($longNames.Count){throw "Список агентов содержит длинные описания вместо ролей: $($longNames.Id -join ', ')"}
    if([Windows.Controls.ScrollViewer]::GetHorizontalScrollBarVisibility((UI 'TeamAgentList'))-ne[Windows.Controls.ScrollBarVisibility]::Disabled){throw 'Горизонтальная прокрутка списка агентов не отключена'}
    Write-Output ("TEAM_TAB_SMOKE_OK | {0} agents | {1:N3} sec" -f (UI 'TeamAgentList').Items.Count,$watch.Elapsed.TotalSeconds)
    $window.Close()
    return
}
$telegramWatchdogTimer.Start()
$timer.Start()
[void]$window.ShowDialog()
