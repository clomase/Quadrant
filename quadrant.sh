#!/bin/bash
set -e

CONFIG_FILE=./Quadrantfile
MACHINES_DIR= #"$HOME/machines_dir"
IF_COUNTER=1 # начало нумерации адресов
CMD=$1
ARG=$2
UTILITY_NAME=quadrant
IN_GUEST_USER=vagrant

if [ -z "$CMD" ]; then
	echo "Вызов $UTILITY_NAME (init | up | status [опционально --all] | ssh [vm_name] | halt | destroy | install | uninstall)"
	exit 255; fi

if [ "$CMD" == "init" ]; then
	if [ ! -f "$CONFIG_FILE" ]; then
		cat > $CONFIG_FILE <<EOF
#	Обязательные переменные для работы утилиты
#	============================================
BASE_DISK=			# Путь до виртуального диска, служащего образцом (например: /home/user/base.qcow2)
SSH_PASS_KEY=		# Путь до соответствующего закрытого SSH-ключа (например: /home/user/.ssh/id_rsa_vagrant)

#	=======================================================
#	Необязательные переменные — если не указаны, скрипт подставит значения по умолчанию
#	=======================================================

# MACHINES_NAMES= 		# node1 по умолчанию
# Список имён виртуальных машин. Можно указать одну:
#   MACHINES_NAMES="app"
# Или несколько:
#   MACHINES_NAMES=("vm1" "vm2" "vm3")
# Если не указать значение, будет присвоено значение по умолчанию node1

# Для каждой машины можно задать индивидуальные параметры, используя префикс в верхнем регистре:
# {VMNAME}_{FIELD_NAME}
# Пример для машины "node1":
# NODE1_CPU="host"
# NODE1_SMP="2"
# NODE1_RAM="2048"
# NODE1_DEMON="FALSE"        # Режим отладки
# NODE1_TIMEOUT="30"         # Время ожидания загрузки системы
# NODE1_SFOLDER="./src"      # Shared Folder
# NODE1_PROVISION=("sh:./scripts/install-docker.sh" "sh:./scripts/init-swarm.sh") # Провижинг

# Доступные настройки для каждой машины:
# {VMNAME}_{FIELD_NAME}
#   _EXECUTOR    # исполняемый файл QEMU (по умолчанию: qemu-system-x86_64)
#   _CPU         # модель CPU (по умолчанию: qemu64)
#   _SMP         # количество ядер (по умолчанию: 1)
#   _RAM         # объём RAM в МБ (по умолчанию: 1024)
#   _NET_DEVICE  # сетевое устройство (по умолчанию: e1000)
#   _ADVICES     # дополнительные флаги QEMU (по умолчанию: -enable-kvm)
#   _GRAPHIC     # графический режим (по умолчанию: -nographic)
#   _DEMON       # запуск в фоне (по умолчанию: TRUE)
#   _TIMEOUT     # таймаут ожидания SSH (по умолчанию: 15)
#	_REPEAT_PROVISION	# опция для разрешения повторения продвинутого провижинга при перезапуске машин
# ===========================
# Опциональные настройки, по умолчанию поля не заданы
# ===========================
#   _SFOLDER     # путь до папки на хосте для копирования в /home/vagrant/
#   _BASE_PROVISION   # массив провижининг-задач в формате "агент:путь_к_скрипту"
#   _ADVANCE_PROVISION   # массив задач, требующих запущенного состояния для всех машин,
#	формат: "агент:путь_к_скрипту"; добавление в массив записи "repeat:multiple" даст возможность
#	повторного выполнения продвинутого провижинга ("агент:путь_к_скрипту" "repeat:multiple")
#   _INTNETS     # массив внутренних сетей в формате ("listen/5555" "connect/5555" "connect/")
#	_ADD_FORWARD	# строка, где перечисляются пробросы через user интерфейс в
#	формате: "hostfwd=tcp::n-:m"; со стороны хоста можно также указать адрес интерфеса

# Пример внутренних сетей (socket-сети между ВМ):
# VM1_INTNETS=("listen/5555")
# VM2_INTNETS=("connect/5555")
# VM3_INTNETS=("connect/")	# Порт сокета можно не указывать, по умолчанию подставится 5555
# Первая машина открывает сокет соединение, последующие присоединяются
#
# Пример дополнительных пробросов портов:
# MANAGER01_ADD_FORWARD="hostfwd=tcp::80-:80"
# MANAGER01_ADD_FORWARD="hostfwd=tcp::80-:80,hostfwd=tcp::443-:443" # несколько пишутся без пробелов через запятую
#
# ============================
# Опции для отладки
# ============================
#	_DEMON			# В значении FALSE выведет лог запуска текущей машины в окне терминала
#	_SSH_DEBUG		# В значении TRUE выведет лог проверки ssh соединения при запуске
EOF
		exit 0;
	else echo "Конфиг для текущей директории уже существует"
		exit 255; fi
fi

conf_check() {
if [ -f $CONFIG_FILE ]; then
	source "$CONFIG_FILE"
else echo "Файл конфигурации не найден в директори"
	return 255; fi
	}

machine_creator() {
	local EXECUTOR="$1"
	local NAME="$2"
	local ADVICES="$3"
	local CPU="$4"
	local SMP="$5"
	local RAM="$6"
	local DISK="$7"
	local PORT="$8"
	local MAC="$9"
	local NET_DEVICE="${10}"
	local GRAPHIC="${11}"
	local FORWARD="${12}"
	shift 12
	local -a ADDNETS=("$@")

	if [ "$FORWARD" != "" ]; then
		FORWARD=",$FORWARD"; fi

	$EXECUTOR \
	-name $NAME \
	$ADVICES \
	-cpu $CPU \
	-smp $SMP \
	-m $RAM \
	-drive file=$DISK,if=virtio,cache=unsafe \
	-netdev user,id=net0,hostfwd=tcp::${PORT}-:22${FORWARD} \
	-device ${NET_DEVICE},netdev=net0,mac=${MAC} \
	$GRAPHIC ${ADDNETS[@]}
	}

iface_create() {
	local INPUT="$1"
	local DEVICE="$2"
	local IFACENUM="$3"
	local VMNUM="$4"
	if [[ $INPUT =~ ^(listen|connect)/.*$ ]]; then
		local MODE=$(cut -f1 -d'/' <<< $INPUT)
		local PORT=$(cut -f2 -d'/' <<< $INPUT)
		if [[ ! $PORT =~ ^[2-9][0-9]{3}[0-9]?$ ]]; then
			PORT=5555; fi
		echo "-netdev socket,id=net${IFACENUM},${MODE}=:${PORT}" \
		"-device ${DEVICE},netdev=net${IFACENUM},mac=52:54:00:$(( 10 + VMNUM )):$(( 10 + IFACENUM )):$(( 10 + IFACENUM ))"
	else
		echo ""; fi
	}

ssh_check() {
	local PORT=$1
	local KEY="$2"
	local DEBUG="$3"
	local IN_GUEST_USER="$4"

	for i in {1..7}; do
		if [ "${DEBUG^^}" == "TRUE" ]; then
			if timeout 20 ssh -o ConnectTimeout=15 -o BatchMode=yes \
				-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
				-o GlobalKnownHostsFile=/dev/null \
				-p "$PORT" -i "$KEY" \
				${IN_GUEST_USER}@localhost true 2>&1; then
				return 0; fi
		else
			if timeout 20 ssh -o ConnectTimeout=15 -o BatchMode=yes \
				-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
				-o GlobalKnownHostsFile=/dev/null \
				-p "$PORT" -i "$KEY" \
				${IN_GUEST_USER}@localhost true >/dev/null 2>&1; then
				return 0; fi
		fi
	done
	return 127
	}

MACHINES_NAMES=${MACHINES_NAMES:-"node1"}
MACHINES_DIR=${MACHINES_DIR:-"$HOME/machines_dir"}
IN_GUEST_USER=${IN_GUEST_USER:-vagrant}

case $CMD in
"up")
	if ! conf_check; then exit 100; fi
	if [[ -n "$BASE_DISK" && -n "$SSH_PASS_KEY" ]]; then
		if [[ -f "$BASE_DISK" && -f "$SSH_PASS_KEY" ]]; then
			echo "Начало работы"
		else
			echo "Не найдены файл диска-источника или файл ссш-ключа"
			exit 255; fi
	else
		echo "Необходимо указать переменную базового-диска и ссш-ключ к нему"
		exit 255; fi

for vm in "${MACHINES_NAMES[@]}"; do
	mkdir -p $MACHINES_DIR/$vm
	if [[ ! -f "$MACHINES_DIR/$vm/disk.qcow2" ]]; then
		echo "Копируем диск..."
		cp $BASE_DISK "$MACHINES_DIR/$vm/disk.qcow2"
		echo "Диск создан"
	else echo "Найден существующий диск для $vm"; fi

	if [[ ! -d "$HOME/.q-drant/machines-info/$vm" ]]; then
		mkdir -p "$HOME/.q-drant/machines-info/$vm"; fi

	TARGET_EXECUTOR="${vm^^}_EXECUTOR"
	TARGET_EXECUTOR=${!TARGET_EXECUTOR}
	TARGET_EXECUTOR=${TARGET_EXECUTOR:-"qemu-system-x86_64"}

	TARGET_CPU="${vm^^}_CPU"
	TARGET_CPU=${!TARGET_CPU}
	TARGET_CPU=${TARGET_CPU:-"qemu64"}

	TARGET_SMP="${vm^^}_SMP"
	TARGET_SMP=${!TARGET_SMP}
	TARGET_SMP=${TARGET_SMP:-"1"}

	TARGET_RAM="${vm^^}_RAM"
	TARGET_RAM=${!TARGET_RAM}
	TARGET_RAM=${TARGET_RAM:-"1024"}

	TARGET_DISK="$MACHINES_DIR/$vm/disk.qcow2" # не забыть поменять на .qcow2

	TARGET_PORT=$(( 2200 + IF_COUNTER ))
	TARGET_MAC="52:54:00:00:$(( 10 + IF_COUNTER )):$(( 10 + IF_COUNTER ))"
	(( IF_COUNTER++ ))

	TARGET_NET_DEVICE="${vm^^}_NET_DEVICE"
	TARGET_NET_DEVICE=${!TARGET_NET_DEVICE}
	TARGET_NET_DEVICE=${TARGET_NET_DEVICE:-"e1000"}

	TARGET_ADD_FORWARD="${vm^^}_ADD_FORWARD"
	TARGET_ADD_FORWARD="${!TARGET_ADD_FORWARD}"

	TARGET_ADVICES="${vm^^}_ADVICES"
	TARGET_ADVICES="${!TARGET_ADVICES}"
	TARGET_ADVICES="${TARGET_ADVICES:-"-enable-kvm"}"

	TARGET_GRAPHIC="${vm^^}_GRAPHIC"
	TARGET_GRAPHIC="${!TARGET_GRAPHIC}"
	TARGET_GRAPHIC="${TARGET_GRAPHIC:-"-nographic"}"

	TARGET_INTNETS="${vm^^}_INTNETS"
	INTNETS="${!TARGET_INTNETS}"
	if [[ -n $INTNETS ]]; then
		declare -n NETS="$TARGET_INTNETS"
		TARGET_ADDNETS=()
		for iface in "${NETS[@]}"; do
			ADD=( $(iface_create $iface $TARGET_NET_DEVICE $((IF_COUNTER - 1)) $IF_COUNTER) )
			TARGET_ADDNETS+=( "${ADD[@]}" )
			(( IF_COUNTER++ ))
		done
	fi

	TARGET_DEMON="${vm^^}_DEMON"
	TARGET_DEMON="${!TARGET_DEMON}"
	TARGET_DEMON="${TARGET_DEMON:-TRUE}"

	if [ "${TARGET_DEMON^^}" == "FALSE" ]; then
		echo "Запуск $vm"
		machine_creator "$TARGET_EXECUTOR" "$vm" "$TARGET_ADVICES" $TARGET_CPU $TARGET_SMP \
 	$TARGET_RAM $TARGET_DISK $TARGET_PORT $TARGET_MAC $TARGET_NET_DEVICE \
 	"$TARGET_GRAPHIC" "$TARGET_ADD_FORWARD" \
 	"${TARGET_ADDNETS[@]}"
	else
		echo "Запуск $vm"
		machine_creator "$TARGET_EXECUTOR" "$vm" "$TARGET_ADVICES" $TARGET_CPU $TARGET_SMP \
 	$TARGET_RAM $TARGET_DISK $TARGET_PORT $TARGET_MAC $TARGET_NET_DEVICE \
 	"$TARGET_GRAPHIC" "$TARGET_ADD_FORWARD" \
 	"${TARGET_ADDNETS[@]}" > $MACHINES_DIR/$vm/qemu.log 2>&1 &
 	fi

	TARGET_TIMEOUT="${vm^^}_TIMEOUT"
	TARGET_TIMEOUT="${!TARGET_TIMEOUT}"
	TARGET_TIMEOUT="${TARGET_TIMEOUT:-15}"
	sleep $TARGET_TIMEOUT

	TARGET_SSH_DEBUG="${vm^^}_SSH_DEBUG"
	TARGET_SSH_DEBUG="${!TARGET_SSH_DEBUG}"
	TARGET_SSH_DEBUG="${TARGET_SSH_DEBUG:-FALSE}"

	if ssh_check ${TARGET_PORT} "$SSH_PASS_KEY" "$TARGET_SSH_DEBUG" $IN_GUEST_USER; then
		echo "Виртуальная машина $vm запущена"
	else
		echo "Машина $vm не отвечает"
		pkill -f "qemu.*-name $vm"
		exit 255; fi

	TARGET_SFOLDER="${vm^^}_SFOLDER"
	TARGET_SFOLDER="${!TARGET_SFOLDER}"
	if [[ -n "$TARGET_SFOLDER" && -d "$TARGET_SFOLDER" ]]; then
		scp -P ${TARGET_PORT} -i ${SSH_PASS_KEY} -o GlobalKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-r "$TARGET_SFOLDER" \
		${IN_GUEST_USER}@localhost:~/ >/dev/null 2>&1
		echo "Выполнен проброс папки"
	fi

	TARGET_BASE_PROVISION="${vm^^}_BASE_PROVISION"
	PROVISIONS="${!TARGET_BASE_PROVISION}"
	if [[ -n "$PROVISIONS" && ! -f "$HOME/.q-drant/machines-info/$vm/info" ]]; then
		declare -n PROVISIONS="$TARGET_BASE_PROVISION"
		for row in "${PROVISIONS[@]}"; do
			if [[ $row == *:* ]]; then
				AGENT=$(cut -f1 -d':' <<< $row)
				TASK=$(cut -f2 -d':' <<< $row)
				if [ -f "$TASK" ]; then
					scp -P ${TARGET_PORT} -i ${SSH_PASS_KEY} \
					-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
					-o GlobalKnownHostsFile=/dev/null \
					"$TASK" ${IN_GUEST_USER}@localhost:~/ >/dev/null 2>&1
					BASETASK=$(basename "$TASK")
					ssh -p ${TARGET_PORT} -i "$SSH_PASS_KEY" \
					-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
					-o GlobalKnownHostsFile=/dev/null \
					${IN_GUEST_USER}@localhost "chmod +x $BASETASK \
					&& $AGENT $BASETASK && rm $BASETASK" >/dev/null 2>&1
				else
					echo "Файл провижининга не найден"; fi
			else
				echo "Формат параметра провижининга не соблюден"; fi
		done
	fi

	cat > "$HOME/.q-drant/machines-info/$vm/info" <<-EOF
	PORT=$TARGET_PORT
	DISK_PATH="$TARGET_DISK"
	EOF
done
	sleep 1
	for on_vm in "${MACHINES_NAMES[@]}"; do
		source "$HOME/.q-drant/machines-info/$on_vm/info"
		ON_PORT=$PORT

		TARGET_REPEAT_PROVISION="${on_vm^^}_REPEAT_PROVISION"
		TARGET_REPEAT_PROVISION="${!TARGET_REPEAT_PROVISION}"
		TARGET_REPEAT_PROVISION="${TARGET_REPEAT_PROVISION:-FALSE}"

		if [[ "${TARGET_REPEAT_PROVISION^^}" == "TRUE" ]]; then
			rm -f "$HOME/.q-drant/machines-info/$on_vm/advance_provisioned" 2>/dev/null; fi

		if [ ! -f "$HOME/.q-drant/machines-info/$on_vm/advance_provisioned" ]; then
		TARGET_ADVANCE_PROVISION="${on_vm^^}_ADVANCE_PROVISION"
		PROVISIONS="${!TARGET_ADVANCE_PROVISION}"
			if [[ -n "$PROVISIONS" ]]; then
				declare -n PROVISIONS="$TARGET_ADVANCE_PROVISION"
				for row in "${PROVISIONS[@]}"; do
					if [[ $row == *:* ]]; then
						AGENT=$(cut -f1 -d':' <<< $row)
						TASK=$(cut -f2 -d':' <<< $row)
						if [ -f "$TASK" ]; then
							echo "Выполняется продвинутый провижининг для $on_vm"
							scp -P ${ON_PORT} -i ${SSH_PASS_KEY} \
							-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
							-o GlobalKnownHostsFile=/dev/null \
							"$TASK" ${IN_GUEST_USER}@localhost:~/ >/dev/null 2>&1
							BASETASK=$(basename "$TASK")
							ssh -p ${ON_PORT} -i "$SSH_PASS_KEY" \
							-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
							-o GlobalKnownHostsFile=/dev/null \
							${IN_GUEST_USER}@localhost "chmod +x $BASETASK \
							&& $AGENT $BASETASK && rm $BASETASK" >/dev/null 2>&1
							sleep 2
							echo "Провижининг выполнен"
						else echo "Файл провижининга не найден"; fi
					else echo "Формат параметра провижининга не соблюден"; fi
				done
				echo "REPEAT=LOCK" > "$HOME/.q-drant/machines-info/$on_vm/advance_provisioned"
			fi
		fi
	done
;;
"status")
	if [ ! -d "$HOME/.q-drant/machines-info" ]; then
		echo "Виртуальные машины еще не создавались"
		exit 511; fi

	names=("$HOME/.q-drant/machines-info"/*/)
	if [[ ! -d "${names[0]}" ]]; then
		echo "Нет сохраненных виртуальных машин"
		exit 511; fi

	if [ "$ARG" == "--all" ]; then
		for vm in "${names[@]}"; do
			if [[ -f "${vm}/info" ]]; then
				source "${vm}/info"
				STATUS_PORT=$PORT
				STATUS_PATH="$DISK_PATH"
				vmname=$(basename $vm)
				if [ -f "$STATUS_PATH" ]; then
					if ssh_check $STATUS_PORT "$SSH_PASS_KEY" "false" $IN_GUEST_USER; then
						echo "${vmname}:${STATUS_PATH}-running"
					else
						echo "${vmname}:${STATUS_PATH}-stopped"; fi
				else echo "${vmname}-not created"; fi
			else echo "Для $vmname не найдено ИНФО"; fi
		done
	else
		if ! conf_check; then exit 100; fi
		for vm in "${MACHINES_NAMES[@]}"; do
			if [[ -f "$HOME/.q-drant/machines-info/${vm}/info" ]]; then
				source "$HOME/.q-drant/machines-info/${vm}/info"
				STATUS_PORT=$PORT
				STATUS_PATH="$DISK_PATH"
				if [ -f "$STATUS_PATH" ]; then
					if ssh_check $STATUS_PORT "$SSH_PASS_KEY" "false" $IN_GUEST_USER; then
						echo "${vm}: running"
					else echo "${vm} stopped"; fi
				else echo "${vm} not created"; fi
			else echo "Для $vm не найдено ИНФО"; fi
		done
	fi
;;
"halt")
	if ! conf_check; then exit 100; fi
	if [ ! -d "$HOME/.q-drant/machines-info" ]; then
		echo "Виртуальные машины еще не создавались"
		exit 511; fi

	names=("$HOME/.q-drant/machines-info"/*/)
	if [[ ! -d "${names[0]}" ]]; then
		echo "Нет сохраненных виртуальных машин"
		exit 511; fi

	for vm in "${MACHINES_NAMES[@]}"; do
		if [ -f "$HOME/.q-drant/machines-info/$vm/info" ]; then
			source "$HOME/.q-drant/machines-info/$vm/info"
			HALT_PORT=$PORT
			ssh -p $HALT_PORT -i $SSH_PASS_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			-o GlobalKnownHostsFile=/dev/null \
			${IN_GUEST_USER}@localhost "sudo shutdown now" \
			>/dev/null 2>&1 || true
			sleep 4
			echo "$vm выключена"
		else echo "$vm не создана"; fi
	done
;;
"destroy")
	if ! conf_check; then exit 100; fi
	if [ ! -d "$HOME/.q-drant/machines-info" ]; then
		echo "Виртуальные машины еще не создавались"
		exit 511; fi

	for vm in "${MACHINES_NAMES[@]}"; do
		if [ -f "$HOME/.q-drant/machines-info/$vm/info" ]; then
			source "$HOME/.q-drant/machines-info/$vm/info"
			DESTROY_PATH="$DISK_PATH"
			if pgrep -af "qemu.* -name $vm " >/dev/null; then
				pkill -f "qemu.* -name $vm "
				sleep 0.5; fi
			rm -f "$DESTROY_PATH"
			rm -rf "$HOME/.q-drant/machines-info/$vm"
			rm -rf "$MACHINES_DIR/$vm"
			echo "$vm стерта"
		else echo "$vm не создана"; fi
	done
;;
"ssh")
	if ! conf_check; then exit 100; fi
	if [ -z "$ARG" ]; then
		exit 1; fi

	if [[ " ${MACHINES_NAMES[@]} " =~ " $ARG " ]]; then
		if [ -f "$HOME/.q-drant/machines-info/$ARG/info" ]; then
			source "$HOME/.q-drant/machines-info/$ARG/info"
			SSH_PORT=$PORT
			if ssh_check $SSH_PORT "$SSH_PASS_KEY" "false" $IN_GUEST_USER; then
				exec ssh -p $SSH_PORT -i $SSH_PASS_KEY -o StrictHostKeyChecking=no \
				-o GlobalKnownHostsFile=/dev/null \
				-o UserKnownHostsFile=/dev/null ${IN_GUEST_USER}@localhost
			else echo "$ARG недоступна"; fi
		else echo "$ARG не создана"; fi
	else echo "$ARG не найдена в конфигурационном файле"; fi
;;
"install")
	source $HOME/.bashrc
	if alias | grep "${UTILITY_NAME}" >/dev/null; then
		echo "Утилита уже установлена"
		exit 1; fi

		mkdir -p "$HOME/.q-drant"
		cp "$0" "$HOME/.q-drant/${UTILITY_NAME}.sh"
		echo "alias ${UTILITY_NAME}=\"bash $HOME/.q-drant/$UTILITY_NAME.sh\"" >> $HOME/.bashrc
		echo "Для завершения установки выполните \"source ~/.bashrc\" или откройте новый терминал"
;;
"uninstall")
	source $HOME/.bashrc
	if cat $HOME/.bashrc | grep -i ${UTILITY_NAME} >/dev/null; then
		grep -vi ${UTILITY_NAME} "$HOME/.bashrc" >> "$HOME/.bashrc-qd-temp"
		mv "$HOME/.bashrc-qd-temp" "$HOME/.bashrc"
		rm -r "$HOME/.q-drant"
		echo "Для завершения удаления выполните \"unalias ${UTILITY_NAME}\" или откройте новый терминал"
	else echo "Не обнаруженно записей в ~/.bashrc, нечего удалять"; fi
;;
esac
